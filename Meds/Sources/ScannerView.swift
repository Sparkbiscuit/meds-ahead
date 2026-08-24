import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
@preconcurrency import Vision
import VisionKit

struct ScannerScreen: View {
    let onComplete: (MedicationDraft) -> Void
    @StateObject private var scannerController = LiveScannerController()
    @State private var evidence: [ScanEvidence] = []
    @State private var preview = ScanPreview()
    @State private var previewTask: Task<Void, Never>?
    @State private var cameraAccess: CameraAccess = .resolving
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isProcessingPhoto = false
    @State private var isInterpreting = false
    @State private var errorMessage: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum CameraAccess: Equatable {
        case resolving
        case authorized
        case denied
        case unavailable
    }

    private var canUseLiveScanner: Bool { cameraAccess == .authorized }

    private var hasUsefulProgress: Bool { preview.hasUsefulProgress }

    private var canReview: Bool {
        (canUseLiveScanner || !evidence.isEmpty)
            && !isProcessingPhoto
            && !isInterpreting
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                scannerArea
                controls
            }
        }
        .navigationTitle("Scan Label")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await resolveCameraAccess() }
        .onChange(of: evidence) { _, newValue in
            schedulePreviewUpdate(for: newValue)
        }
        .onDisappear { previewTask?.cancel() }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            processPhoto(item)
        }
        .alert("Couldn’t Read This Label", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Try a sharper view with less glare, or enter the medication manually.")
        }
    }

    private var scannerArea: some View {
        ZStack {
            if canUseLiveScanner {
                LiveDataScanner(evidence: $evidence, controller: scannerController)
                    .ignoresSafeArea(edges: .top)
            } else {
                LinearGradient(colors: [.black, Color(red: 0.06, green: 0.11, blue: 0.14)], startPoint: .top, endPoint: .bottom)
                unavailableScannerMessage
            }

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    hasUsefulProgress ? Color.green : .white.opacity(0.72),
                    style: StrokeStyle(lineWidth: 2, dash: hasUsefulProgress ? [] : [9, 8])
                )
                .padding(.horizontal, ScanFrameLayout.horizontalInset)
                .padding(.vertical, ScanFrameLayout.verticalInset)
                .allowsHitTesting(false)
                .animation(reduceMotion ? nil : .medsSpring, value: hasUsefulProgress)

            VStack(spacing: 10) {
                scanProgress
                Spacer()
                Text(scanGuidance)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.52), in: Capsule())
                    .padding(.bottom, 24)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var scanProgress: some View {
        if hasUsefulProgress {
            HStack(spacing: 7) {
                if !preview.medicationName.isEmpty {
                    ScanProgressPill(title: "Name", systemImage: "pills.fill")
                }
                if preview.hasStrength {
                    ScanProgressPill(title: "Strength", systemImage: "checkmark")
                }
                if preview.hasQuantity {
                    ScanProgressPill(title: "Quantity", systemImage: "number")
                }
                if preview.hasProductIdentifier {
                    ScanProgressPill(title: "Code", systemImage: "barcode")
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, 12)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var scanGuidance: String {
        if !preview.medicationName.isEmpty { return "Name matched — rotate for strength, quantity, and refill details" }
        if !evidence.isEmpty { return "Keep rotating until the full medication name is visible" }
        return "Keep the label inside the frame and slowly rotate the bottle"
    }

    private var controls: some View {
        VStack(spacing: 13) {
            if isProcessingPhoto || isInterpreting {
                ProgressView(isInterpreting ? "Organizing label on this iPhone…" : "Reading photo…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Choose Photo", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.white)
                .disabled(isInterpreting)

                Button(action: reviewScan) {
                    Label(evidence.isEmpty ? "Capture & Review" : "Review", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canReview)
            }
            Button("Clear Scan", action: clearScan)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
                .disabled(
                    evidence.isEmpty || isInterpreting
                )
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var unavailableScannerMessage: some View {
        if cameraAccess == .resolving {
            // Nothing is known yet; claiming the camera is unavailable here would
            // flash the wrong explanation on the way in.
            ProgressView()
                .tint(.white)
                .controlSize(.large)
        } else {
            deniedOrUnsupportedMessage
        }
    }

    private var deniedOrUnsupportedMessage: some View {
        VStack(spacing: 14) {
            Image(systemName: cameraAccess == .denied ? "lock.circle" : "camera.metering.unknown")
                .font(.system(size: 48))
            Text(cameraAccess == .denied ? "Camera access is off" : "Live scanning isn’t available here")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(cameraAccess == .denied
                 ? "Meds Ahead needs the camera to read a label. You can turn it on in Settings, or choose a clear photo of the label instead."
                 : "Choose a clear photo of the label, or use live scanning on a supported iPhone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
            if cameraAccess == .denied {
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .foregroundStyle(.white)
    }

    /// Resolved once, up front, so a refusal lands on an explanatory screen with a
    /// route to Settings instead of a black frame behind "keep the label inside
    /// the frame".
    @MainActor
    private func resolveCameraAccess() async {
        guard cameraAccess == .resolving else { return }
        guard DataScannerViewController.isSupported else {
            cameraAccess = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAccess = DataScannerViewController.isAvailable ? .authorized : .unavailable
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraAccess = granted
                ? (DataScannerViewController.isAvailable ? .authorized : .unavailable)
                : .denied
        case .denied, .restricted:
            cameraAccess = .denied
        @unknown default:
            cameraAccess = .unavailable
        }
    }

    /// Recomputing the overlay facts costs a full pipeline run against the bundled
    /// vocabulary, and live scanning republishes evidence continuously. Debounce,
    /// run it off the main actor, and cancel any run the next update supersedes.
    private func schedulePreviewUpdate(for evidence: [ScanEvidence]) {
        previewTask?.cancel()
        guard !evidence.isEmpty else {
            preview = ScanPreview()
            return
        }
        previewTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let computed = await Task.detached(priority: .userInitiated) {
                ScanPreview.make(from: evidence)
            }.value
            guard !Task.isCancelled else { return }
            preview = computed
        }
    }

    private func reviewScan() {
        isInterpreting = true
        Task { @MainActor in
            var finalEvidence = evidence
            if canUseLiveScanner {
                do {
                    let image = try await scannerController.captureCroppedPhoto()
                    let captured = try await StillImageRecognizer.recognize(image: image, origin: .cameraCapture)
                    finalEvidence = ScanEvidenceQuality.mergingBest(existing: finalEvidence, additions: captured)
                } catch where finalEvidence.isEmpty {
                    isInterpreting = false
                    errorMessage = "The camera couldn’t capture a sharp label. Hold the bottle steady inside the frame and try again."
                    return
                } catch {
                    // Stable evidence already exists, so confirmation remains
                    // available even if the final snapshot fails unexpectedly.
                }
            }

            guard !finalEvidence.isEmpty else {
                isInterpreting = false
                errorMessage = "No trustworthy label text or code was found. Move closer, reduce glare, and keep the medication name inside the frame."
                return
            }

            evidence = finalEvidence
            scannerController.stopScanning()
            let draft = await MedicationLabelInterpreter.interpret(finalEvidence)
            isInterpreting = false
            onComplete(draft)
        }
    }

    private func processPhoto(_ item: PhotosPickerItem) {
        isProcessingPhoto = true
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ScannerError.unreadableImage
                }
                let found = try await StillImageRecognizer.recognize(data: data, origin: .photoLibrary)
                await MainActor.run {
                    merge(found)
                    isProcessingPhoto = false
                    selectedPhoto = nil
                    if found.isEmpty {
                        errorMessage = "No trustworthy Latin label text or code was found. Try a sharper, wider photo with less glare."
                    }
                }
            } catch {
                await MainActor.run {
                    isProcessingPhoto = false
                    selectedPhoto = nil
                    errorMessage = "No readable label text or code was found. Try a sharper, wider photo with less glare."
                }
            }
        }
    }

    private func merge(_ additions: [ScanEvidence]) {
        let merged = ScanEvidenceQuality.mergingBest(existing: evidence, additions: additions)
        if merged != evidence {
            evidence = merged
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
    }

    private func clearScan() {
        previewTask?.cancel()
        evidence.removeAll()
        preview = ScanPreview()
        scannerController.resetTracking()
        scannerController.startScanning()
    }
}

private struct ScanProgressPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
    }
}

private enum ScannerError: Error {
    case unreadableImage
    case scannerUnavailable
    case invalidCapture
}

@MainActor
private final class LiveScannerController: ObservableObject {
    private weak var scanner: DataScannerViewController?
    private var resetHandler: (() -> Void)?

    func attach(_ scanner: DataScannerViewController, resetHandler: @escaping () -> Void) {
        self.scanner = scanner
        self.resetHandler = resetHandler
    }

    func detach(_ scanner: DataScannerViewController) {
        guard self.scanner === scanner else { return }
        self.scanner = nil
        resetHandler = nil
    }

    func startScanning() {
        guard let scanner, !scanner.isScanning else { return }
        try? scanner.startScanning()
    }

    func stopScanning() {
        scanner?.stopScanning()
    }

    func resetTracking() {
        resetHandler?()
    }

    func captureCroppedPhoto() async throws -> UIImage {
        guard let scanner else { throw ScannerError.scannerUnavailable }
        let image = try await scanner.capturePhoto()
        let viewSize = scanner.view.bounds.size
        let visibleRect = scanner.regionOfInterest ?? scanner.view.bounds
        guard let sourceRect = AspectFillCropMapper.sourceRect(
            imageSize: image.size,
            displayedIn: viewSize,
            visibleRect: visibleRect
        ), let cropped = image.cropped(to: sourceRect) else {
            throw ScannerError.invalidCapture
        }
        return cropped
    }
}

private extension UIImage {
    func cropped(to sourceRect: CGRect) -> UIImage? {
        guard sourceRect.width > 0, sourceRect.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: sourceRect.size, format: format).image { _ in
            draw(at: CGPoint(x: -sourceRect.minX, y: -sourceRect.minY))
        }
    }
}

private struct LiveDataScanner: UIViewControllerRepresentable {
    @Binding var evidence: [ScanEvidence]
    let controller: LiveScannerController

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let supported = Set(DataScannerViewController.supportedTextRecognitionLanguages)
        let preferredLanguages = ["en-US", "es-ES", "fr-FR"].filter(supported.contains)
        let textType: DataScannerViewController.RecognizedDataType = preferredLanguages.isEmpty
            ? .text()
            : .text(languages: preferredLanguages)
        let scanner = DataScannerViewController(
            recognizedDataTypes: [textType, .barcode()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        controller.attach(scanner) { [weak coordinator = context.coordinator] in
            coordinator?.reset()
        }
        context.coordinator.startScanning(scanner)
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.configureRegion(for: uiViewController)
    }

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        coordinator.cancelPendingWork()
        uiViewController.stopScanning()
        uiViewController.delegate = nil
        coordinator.parent.controller.detach(uiViewController)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: LiveDataScanner
        private var tracker = LiveEvidenceTracker<RecognizedItem.ID>()
        private var publishedLiveEvidenceIDs: Set<UUID> = []
        private var promotionTask: Task<Void, Never>?
        private var scannerStartTask: Task<Void, Never>?

        init(parent: LiveDataScanner) {
            self.parent = parent
        }

        func configureRegion(for scanner: DataScannerViewController) {
            let region = ScanFrameLayout.region(in: scanner.view.bounds)
            guard region.width > 0, region.height > 0, scanner.regionOfInterest != region else { return }
            scanner.regionOfInterest = region
        }

        func startScanning(_ scanner: DataScannerViewController) {
            scannerStartTask?.cancel()
            scannerStartTask = Task { @MainActor [weak self, weak scanner] in
                await Task.yield()
                guard let self, let scanner else { return }
                configureRegion(for: scanner)
                for attempt in 0..<8 {
                    guard !Task.isCancelled else { return }
                    do {
                        if !scanner.isScanning {
                            try scanner.startScanning()
                        }
                        return
                    } catch {
                        let backoff = 120 + (attempt * 80)
                        try? await Task.sleep(for: .milliseconds(backoff))
                    }
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            refresh(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            refresh(allItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            refresh(allItems)
        }

        func reset() {
            promotionTask?.cancel()
            tracker.reset()
            publishedLiveEvidenceIDs.removeAll()
        }

        func cancelPendingWork() {
            promotionTask?.cancel()
            scannerStartTask?.cancel()
        }

        private func refresh(_ items: [RecognizedItem]) {
            let observations = items.compactMap(makeObservation)
            let update = tracker.update(observations, at: ProcessInfo.processInfo.systemUptime)
            publish(update)
            schedulePromotion()
        }

        private func schedulePromotion() {
            promotionTask?.cancel()
            promotionTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(425))
                guard !Task.isCancelled, let self else { return }
                publish(tracker.promote(at: ProcessInfo.processInfo.systemUptime))
            }
        }

        private func publish(_ update: LiveEvidenceUpdate) {
            let nonLiveEvidence = parent.evidence.filter { !publishedLiveEvidenceIDs.contains($0.id) }
            let merged = ScanEvidenceQuality.mergingBest(existing: nonLiveEvidence, additions: update.evidence)
            publishedLiveEvidenceIDs = Set(update.evidence.map(\.id))
            if merged != parent.evidence { parent.evidence = merged }
            if update.promotedNewEvidence {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            }
        }

        private func makeObservation(_ item: RecognizedItem) -> LiveEvidenceObservation<RecognizedItem.ID>? {
            let evidence: ScanEvidence
            switch item {
            case .text(let text):
                let candidates = text.observation.topCandidates(3)
                if let candidate = candidates.first(where: { LabelTextPolicy.sanitized($0.string) != nil }) {
                    evidence = ScanEvidence(
                        kind: .text,
                        value: candidate.string,
                        confidence: Double(candidate.confidence),
                        origin: .liveCamera
                    )
                } else if LabelTextPolicy.sanitized(text.transcript) != nil {
                    evidence = ScanEvidence(
                        kind: .text,
                        value: text.transcript,
                        confidence: 0.5,
                        origin: .liveCamera
                    )
                } else {
                    return nil
                }
            case .barcode(let barcode):
                guard let payload = barcode.payloadStringValue, !payload.isEmpty else { return nil }
                evidence = ScanEvidence(
                    kind: .barcode,
                    value: payload,
                    symbology: barcode.observation.symbology.rawValue,
                    confidence: Double(barcode.observation.confidence),
                    origin: .liveCamera
                )
            @unknown default:
                return nil
            }
            return LiveEvidenceObservation(id: item.id, evidence: evidence)
        }
    }
}

enum StillImageRecognizer {
    static func recognize(data: Data, origin: ScanEvidence.Origin) async throws -> [ScanEvidence] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let handler = VNImageRequestHandler(data: data, options: [:])
                    let recognized = try performRecognition(handler: handler)
                    continuation.resume(returning: makeEvidence(from: recognized, origin: origin))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func recognize(image: UIImage, origin: ScanEvidence.Origin) async throws -> [ScanEvidence] {
        guard let cgImage = image.cgImage else { throw ScannerError.unreadableImage }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let handler = VNImageRequestHandler(
                        cgImage: cgImage,
                        orientation: orientation,
                        options: [:]
                    )
                    let recognized = try performRecognition(handler: handler)
                    continuation.resume(returning: makeEvidence(from: recognized, origin: origin))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private struct RecognitionResult {
        let text: [VNRecognizedTextObservation]
        let barcodes: [VNBarcodeObservation]

    }

    private static func performRecognition(handler: VNImageRequestHandler) throws -> RecognitionResult {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.recognitionLanguages = ["en-US"]
        let barcodeRequest = VNDetectBarcodesRequest()
        try handler.perform([textRequest])
        // Barcode inference is optional and can be unavailable even when OCR succeeds.
        // Never discard usable medication text because a code model could not initialize.
        try? handler.perform([barcodeRequest])
        return RecognitionResult(
            text: textRequest.results ?? [],
            barcodes: barcodeRequest.results ?? []
        )
    }

    private static func makeEvidence(
        from result: RecognitionResult,
        origin: ScanEvidence.Origin
    ) -> [ScanEvidence] {
        let captureID = UUID()
        let sortedText = result.text.sorted { lhs, rhs in
            if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.02 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        var evidence = sortedText.enumerated().compactMap { index, observation -> ScanEvidence? in
            guard let candidate = observation.topCandidates(3).first(where: {
                $0.confidence >= 0.25 && LabelTextPolicy.sanitized($0.string) != nil
            }), let value = LabelTextPolicy.sanitized(candidate.string) else { return nil }
            return ScanEvidence(
                kind: .text,
                value: value,
                confidence: Double(candidate.confidence),
                origin: origin,
                captureID: captureID,
                lineIndex: index
            )
        }
        evidence.append(contentsOf: result.barcodes.compactMap { observation in
            guard let payload = observation.payloadStringValue, !payload.isEmpty else { return nil }
            return ScanEvidence(
                kind: .barcode,
                value: payload,
                symbology: observation.symbology.rawValue,
                confidence: Double(observation.confidence),
                origin: origin,
                captureID: captureID
            )
        })
        return ScanEvidenceQuality.mergingBest(existing: [], additions: evidence)
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
