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
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: scenePhase) { _, phase in
            guard canUseLiveScanner else { return }
            if phase == .active {
                // Backgrounding (or a phone call) stops the capture session and
                // VisionKit does not restart it on its own; without this, coming
                // back to the scanner shows a frozen frame.
                scannerController.startScanning()
            } else {
                scannerController.setTorch(false)
            }
        }
        .onAppear {
            // No-op on first appearance (the scanner starts itself when it
            // attaches); resumes live scanning when popping back from review,
            // which previously left a frozen frame until Clear Scan.
            scannerController.startScanning()
        }
        .onDisappear {
            previewTask?.cancel()
            scannerController.setTorch(false)
        }
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
                LiveDataScanner(
                    evidence: $evidence,
                    controller: scannerController,
                    // Swaps to the photo-fallback explanation; recognized
                    // evidence is kept and Review stays available.
                    onBecameUnavailable: { cameraAccess = .unavailable }
                )
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
                .padding(.top, ScanFrameLayout.topInset)
                .padding(.bottom, ScanFrameLayout.bottomInset)
                .allowsHitTesting(false)
                .animation(reduceMotion ? nil : .medsSpring, value: hasUsefulProgress)

            VStack(spacing: 10) {
                scanProgress
                Spacer()
            }
        }
        .overlay(alignment: .bottom) {
            if let scanGuidance {
                Text(scanGuidance)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.horizontal, ScanFrameLayout.horizontalInset)
                    .padding(.bottom, 14)
            }
        }
        .animation(reduceMotion ? nil : .medsSpring, value: scanGuidance)
        .overlay(alignment: .bottomTrailing) { torchButton }
        .accessibilityElement(children: .contain)
    }

    /// Low light is the most common reason a legible label fails to read, and the
    /// system scanner offers no flashlight control of its own.
    @ViewBuilder
    private var torchButton: some View {
        if canUseLiveScanner && scannerController.isTorchAvailable {
            Button {
                scannerController.toggleTorch()
            } label: {
                Image(systemName: scannerController.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(scannerController.isTorchOn ? .black : .white)
                    .frame(width: 44, height: 44)
                    .background(
                        scannerController.isTorchOn ? AnyShapeStyle(.white) : AnyShapeStyle(.black.opacity(0.52)),
                        in: Circle()
                    )
            }
            .accessibilityLabel(scannerController.isTorchOn ? "Turn flashlight off" : "Turn flashlight on")
            .padding(.trailing, ScanFrameLayout.horizontalInset + 12)
            .padding(.bottom, ScanFrameLayout.bottomInset + 12)
        }
    }

    @ViewBuilder
    private var scanProgress: some View {
        if hasUsefulProgress {
            ScanProgressFlow(spacing: 7, rowSpacing: 7) {
                if !preview.medicationName.isEmpty {
                    ScanProgressPill(title: "Name", systemImage: "pills.fill")
                }
                if preview.hasStrength {
                    ScanProgressPill(title: "Strength", systemImage: "checkmark")
                }
                if preview.hasQuantity {
                    ScanProgressPill(title: "Quantity", systemImage: "number")
                }
                if preview.hasRefills {
                    ScanProgressPill(title: "Refills", systemImage: "arrow.clockwise")
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

    /// Guidance must match the input actually available: telling someone to
    /// rotate a bottle in front of a camera that is off is worse than silence.
    private var scanGuidance: String? {
        // Only the facts every label carries. A refill count is absent from an OTC
        // bottle altogether, so asking for one left the banner nagging forever.
        let missing = [
            preview.medicationName.isEmpty ? "name" : nil,
            !preview.hasStrength ? "strength" : nil,
            !preview.hasQuantity ? "quantity" : nil
        ].compactMap { $0 }
        let missingDescription: String = {
            switch missing.count {
            case 0:
                return ""
            case 1:
                return missing[0]
            case 2:
                return missing.joined(separator: " and ")
            default:
                return missing.dropLast().joined(separator: ", ") + " and " + (missing.last ?? "")
            }
        }()

        if canUseLiveScanner {
            if evidence.isEmpty { return "Keep the label inside the frame and slowly rotate the bottle" }
            if missing.isEmpty { return "Everything found — tap Review" }
            if preview.medicationName.isEmpty { return "Keep rotating until the full medication name is visible" }
            return "Found the name. Keep rotating for \(missingDescription)"
        }
        guard !evidence.isEmpty else { return nil }
        if missing.isEmpty { return "Everything found — tap Review" }
        if preview.medicationName.isEmpty { return "Add a photo where the full medication name is visible" }
        return "Found the name. Add a photo of the other sides for \(missingDescription)"
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

/// Pills keep their own size and wrap onto another row. An `HStack` squeezes
/// every pill the moment a fifth one appears, which is exactly when the labels
/// carry the most information and are least readable compressed.
private struct ScanProgressFlow: Layout {
    var spacing: CGFloat = 7
    var rowSpacing: CGFloat = 7

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } + rowSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: min(rows.map(\.width).max() ?? 0, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews: subviews, maxWidth: bounds.width) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func rows(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extended = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if !current.indices.isEmpty, extended > maxWidth {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = extended
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

private struct ScanProgressPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
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
    @Published private(set) var isTorchAvailable = false
    @Published private(set) var isTorchOn = false
    private weak var scanner: DataScannerViewController?
    private var resetHandler: (() -> Void)?
    private var restartHandler: (() -> Void)?
    private var torchRecoveryTask: Task<Void, Never>?

    func attach(
        _ scanner: DataScannerViewController,
        resetHandler: @escaping () -> Void,
        restartHandler: @escaping () -> Void
    ) {
        self.scanner = scanner
        self.resetHandler = resetHandler
        self.restartHandler = restartHandler
        isTorchAvailable = AVCaptureDevice.default(for: .video)?.hasTorch == true
    }

    func detach(_ scanner: DataScannerViewController) {
        guard self.scanner === scanner else { return }
        self.scanner = nil
        resetHandler = nil
        restartHandler = nil
        torchRecoveryTask?.cancel()
        isTorchAvailable = false
        isTorchOn = false
    }

    func startScanning() {
        guard let scanner, !scanner.isScanning else { return }
        restartHandler?()
    }

    func stopScanning() {
        setTorch(false)
        scanner?.stopScanning()
    }

    func resetTracking() {
        resetHandler?()
    }

    func toggleTorch() {
        setTorch(!isTorchOn)
    }

    /// The torch must be driven on the same AVCaptureDevice instance VisionKit's
    /// session uses, found through its preview layer. Locking a second instance
    /// of the camera (AVCaptureDevice.default) interrupts the running session on
    /// real hardware, which froze the live preview whenever the torch was on.
    /// The system shuts the torch off whenever the session stops; state is
    /// re-synced on those paths.
    func setTorch(_ on: Bool) {
        guard let device = sessionCaptureDevice() ?? AVCaptureDevice.default(for: .video),
              device.hasTorch else {
            isTorchOn = false
            return
        }
        do {
            try device.lockForConfiguration()
            device.torchMode = on && device.isTorchAvailable ? .on : .off
            device.unlockForConfiguration()
            isTorchOn = device.torchMode == .on
        } catch {
            isTorchOn = false
        }
        if on { scheduleTorchRecoveryNudge() }
    }

    private func sessionCaptureDevice() -> AVCaptureDevice? {
        guard let scanner,
              let preview = Self.previewLayer(in: scanner.view.layer),
              let session = preview.session else { return nil }
        return session.inputs
            .compactMap { ($0 as? AVCaptureDeviceInput)?.device }
            .first(where: \.hasTorch)
    }

    private static func previewLayer(in layer: CALayer) -> AVCaptureVideoPreviewLayer? {
        if let preview = layer as? AVCaptureVideoPreviewLayer { return preview }
        for sublayer in layer.sublayers ?? [] {
            if let found = previewLayer(in: sublayer) { return found }
        }
        return nil
    }

    /// Belt and suspenders: if toggling the torch still interrupted the session,
    /// scanning stops — restart it rather than leave a frozen frame.
    private func scheduleTorchRecoveryNudge() {
        torchRecoveryTask?.cancel()
        torchRecoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !Task.isCancelled else { return }
            if let scanner = self.scanner, !scanner.isScanning {
                self.restartHandler?()
            }
        }
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
    let onBecameUnavailable: () -> Void

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
        controller.attach(
            scanner,
            resetHandler: { [weak coordinator = context.coordinator] in
                coordinator?.reset()
            },
            restartHandler: { [weak coordinator = context.coordinator, weak scanner] in
                guard let scanner else { return }
                coordinator?.startScanning(scanner)
            }
        )
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

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            // Without this, a session killed mid-scan (thermal pressure, another
            // app claiming the camera) leaves a frozen frame behind guidance that
            // says to keep rotating the bottle.
            cancelPendingWork()
            parent.onBecameUnavailable()
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
        // Match the live scanner's language set so a photo of the same label
        // reads the same way the camera does.
        textRequest.recognitionLanguages = ["en-US", "es-ES", "fr-FR"]
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
