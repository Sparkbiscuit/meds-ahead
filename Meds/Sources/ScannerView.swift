import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
@preconcurrency import Vision
import VisionKit

struct ScannerScreen: View {
    /// What this run of scans has put away so far, shown under the camera once
    /// there is something to show.
    let tally: SetupSessionTally
    /// Ends the run of scans; offered with the tally.
    let onDone: (() -> Void)?
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
    @State private var pillRowHeight: CGFloat = 0
    @State private var outlineFrame: CGRect = .zero
    @State private var scannerFrame: CGRect = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private static let scanAreaSpace = "scanArea"

    init(
        tally: SetupSessionTally = SetupSessionTally(),
        onDone: (() -> Void)? = nil,
        onComplete: @escaping (MedicationDraft) -> Void
    ) {
        self.tally = tally
        self.onDone = onDone
        self.onComplete = onComplete
    }

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

    /// The frame's top edge, measured from the pill row above it rather than
    /// assumed: the pills wrap onto a second row at large text sizes, and a frame
    /// sized for one row had the second row lying across it.
    private var frameTopInset: CGFloat { ScanFrameLayout.topInset(forPillRowHeight: pillRowHeight) }

    /// The drawn outline in the scanner's own coordinates. The scanner view reaches
    /// up under the navigation bar while the outline does not, so the two frames
    /// are measured in one space and the difference is taken out here; this is
    /// the one rectangle both the green frame and the recognition region are.
    private var recognitionRegion: CGRect {
        guard outlineFrame.width > 0, outlineFrame.height > 0, scannerFrame.width > 0 else { return .zero }
        return outlineFrame.offsetBy(dx: -scannerFrame.minX, dy: -scannerFrame.minY)
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
        .task {
            NDCDirectory.warmUp()
            RxNormTable.warmUp()
            await resolveCameraAccess()
        }
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
                    regionOfInterest: recognitionRegion,
                    // Swaps to the photo-fallback explanation; recognized
                    // evidence is kept and Review stays available.
                    onBecameUnavailable: { cameraAccess = .unavailable }
                )
                .ignoresSafeArea(edges: .top)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(Self.scanAreaSpace))
                } action: { scannerFrame = $0 }
            } else {
                LinearGradient(colors: [.black, Color(red: 0.06, green: 0.11, blue: 0.14)], startPoint: .top, endPoint: .bottom)
                unavailableScannerMessage
            }

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    hasUsefulProgress ? Color.green : .white.opacity(0.72),
                    style: StrokeStyle(lineWidth: 2, dash: hasUsefulProgress ? [] : [9, 8])
                )
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(Self.scanAreaSpace))
                } action: { outlineFrame = $0 }
                .padding(.horizontal, ScanFrameLayout.horizontalInset)
                .padding(.top, frameTopInset)
                .padding(.bottom, ScanFrameLayout.bottomInset)
                .allowsHitTesting(false)
                .animation(reduceMotion ? nil : .medsSpring, value: hasUsefulProgress)

            VStack(spacing: 10) {
                scanProgress
                Spacer()
            }
        }
        .coordinateSpace(.named(Self.scanAreaSpace))
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

    /// All four facts, always on screen. Pills that appeared only once found gave
    /// no sense of what was still outstanding, and the row changed width every time
    /// one arrived. Standing there dimmed, they say what the scanner is looking for
    /// before it finds any of it.
    ///
    /// A barcode has no pill of its own. A manufacturer code that carries the
    /// product's NDC resolves through the same directory as printed digits and
    /// shows up here as the Name pill's exact-match state; a pharmacy's Rx-number
    /// barcode changes nothing, so announcing codes in general only asked someone
    /// to keep turning a bottle for a fact that changes nothing. The exact-match
    /// state changes the pill's symbol and nothing else: retitling it "Exact
    /// match" widened the row into a second line that lay across the frame, and
    /// the guidance banner already says it in words.
    private var scanProgress: some View {
        ScanProgressFlow(spacing: 7, rowSpacing: 7) {
            ScanProgressPill(
                title: "Name",
                systemImage: "pills.fill",
                isFound: !preview.medicationName.isEmpty,
                isExactMatch: preview.isExactMatch
            )
            ScanProgressPill(title: "Strength", systemImage: "scalemass.fill", isFound: preview.hasStrength)
            ScanProgressPill(title: "Quantity", systemImage: "number", isFound: preview.hasQuantity)
            ScanProgressPill(title: "Refills", systemImage: "arrow.clockwise", isFound: preview.hasRefills)
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { pillRowHeight = $0 }
        // Clear of the system scanner's own "Slow down" hint, which sits just under
        // the title and was reading through the pills.
        .padding(.top, ScanFrameLayout.pillRowTop)
        .padding(.horizontal, 12)
        .animation(reduceMotion ? nil : .medsSpring, value: preview)
    }

    /// Guidance must match the input actually available: telling someone to
    /// rotate a bottle in front of a camera that is off is worse than silence.
    private var scanGuidance: String? {
        // The same four facts the pills show. A banner that said everything was
        // found while a pill sat dimmed above it contradicted the screen.
        let missing = [
            preview.medicationName.isEmpty ? "name" : nil,
            !preview.hasStrength ? "strength" : nil,
            !preview.hasQuantity ? "quantity" : nil,
            !preview.hasRefills ? "refill count" : nil
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

        let nameFound = preview.isExactMatch ? "Exact match from the label's code" : "Found the name"
        if canUseLiveScanner {
            if evidence.isEmpty { return "Keep the label inside the frame and slowly rotate the bottle" }
            // The NDC is the smallest print on the label and the one line worth a
            // second look: Review captures a full-resolution frame, so holding it
            // in view is what turns a read name into an exact product.
            if missing.isEmpty {
                return preview.isExactMatch
                    ? "Everything found — tap Review"
                    : "Everything found — tap Review. If the label prints an NDC, hold that line in frame for an exact match"
            }
            if preview.medicationName.isEmpty { return "Keep rotating until the full medication name is visible" }
            return "\(nameFound). Keep rotating for \(missingDescription)"
        }
        guard !evidence.isEmpty else { return nil }
        if missing.isEmpty { return "Everything found — tap Review" }
        if preview.medicationName.isEmpty { return "Add a photo where the full medication name is visible" }
        return "\(nameFound). Add a photo of the other sides for \(missingDescription)"
    }

    private var controls: some View {
        VStack(spacing: 13) {
            sessionTally
            if isProcessingPhoto || isInterpreting {
                ProgressView(isInterpreting ? "Organizing label on this iPhone…" : "Reading photo…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
            HStack(spacing: 12) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Choose Photo", systemImage: "photo")
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.white)
                .disabled(isInterpreting)

                Button(action: reviewScan) {
                    // "Capture & Review" needs the whole half-width to itself; with
                    // the arrow beside it the label truncated. The arrow belongs to
                    // the shorter title anyway, where it reads as "onward".
                    Group {
                        if evidence.isEmpty {
                            Text("Capture & Review")
                        } else {
                            Label("Review", systemImage: "arrow.right")
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(AppTheme.onAccent)
                .controlSize(.large)
                .disabled(!canReview)
            }
            Button("Clear Scan", action: clearScan)
                .font(.footnote.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .buttonBorderShape(.capsule)
                .tint(.white)
                .disabled(
                    evidence.isEmpty || isInterpreting
                )
#if DEBUG
            if SimulatedScan.isScannerButtonEnabled {
                Button("Simulate Scan") { merge(SimulatedScan.nextEvidence()) }
                    .font(.footnote.weight(.semibold))
                    .tint(.white)
                    .accessibilityIdentifier("simulate-scan")
            }
#endif
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    /// Down here with the buttons rather than over the camera: anything drawn
    /// across the frame sits between the label and the person lining it up.
    /// Its text stops growing at the first accessibility size, because every
    /// line it gains is taken from the camera's frame; VoiceOver reads it
    /// whole, and a long press shows it, and Done, large.
    @ViewBuilder
    private var sessionTally: some View {
        if let summary = tally.summary() {
            HStack(spacing: 12) {
                Label(summary, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(summary)
                    .accessibilityShowsLargeContentViewer()
                    .accessibilityIdentifier("setup-tally")
                if let onDone {
                    Button("Done", action: onDone)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(.white)
                        .accessibilityHint("Closes Add. Everything listed is saved.")
                        .accessibilityShowsLargeContentViewer()
                        .accessibilityIdentifier("setup-done")
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
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
                .foregroundStyle(AppTheme.onAccent)
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
            // A failed capture is swallowed on purpose when live evidence exists,
            // which also hides it from anyone debugging a bottle. The note says
            // what the capture did; the review screen shows it in debug builds.
            var captureNote = "No live capture: evidence came from photos"
            if canUseLiveScanner {
                do {
                    let frame = try await scannerController.captureCroppedPhoto()
                    let captured = try await StillImageRecognizer.recognizeWithReport(image: frame.image, origin: .cameraCapture)
                    let liveCount = finalEvidence.count
                    // The capture leads the merge. It is the full-resolution reading
                    // of the label and carries the line order the parser joins
                    // wrapped text with, so it must never be what the evidence cap
                    // cuts; the live items dedupe into it and fill in behind.
                    finalEvidence = ScanEvidenceQuality.mergingBest(existing: captured.evidence, additions: finalEvidence)
                    captureNote = "Review capture: \(frame.description); \(captured.report); \(liveCount) live items, \(finalEvidence.count) after merging (cap \(ScanEvidenceQuality.evidenceLimit))"
                } catch where finalEvidence.isEmpty {
                    isInterpreting = false
                    errorMessage = "The camera couldn’t capture a sharp label. Hold the bottle steady inside the frame and try again."
                    return
                } catch {
                    // Stable evidence already exists, so confirmation remains
                    // available even if the final snapshot fails unexpectedly.
                    captureNote = "Review capture failed: \(error)"
                }
            }

            guard !finalEvidence.isEmpty else {
                isInterpreting = false
                errorMessage = "No trustworthy label text or code was found. Move closer, reduce glare, and keep the medication name inside the frame."
                return
            }

            evidence = finalEvidence
            scannerController.stopScanning()
            var draft = await MedicationLabelInterpreter.interpret(finalEvidence)
            draft.captureNote = captureNote
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
    let isFound: Bool
    var isExactMatch = false

    private var symbolName: String {
        if isExactMatch { return "checkmark.seal.fill" }
        return isFound ? "checkmark" : systemImage
    }

    private var accessibilityText: String {
        if isExactMatch { return "\(title), exact match" }
        return isFound ? "\(title) found" : "\(title) not found yet"
    }

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .fixedSize()
            // The checkmark carries the state on its own, so the green reads as
            // confirmation rather than as the only thing saying so.
            .foregroundStyle(.white.opacity(isFound ? 1 : 0.62))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(isFound ? Color.green : .white.opacity(0.18), lineWidth: 1.5)
            }
            .accessibilityLabel(accessibilityText)
    }
}

private enum ScannerError: Error {
    case unreadableImage
    case scannerUnavailable
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

    /// What the Review capture produced, in the words a diagnostic wants: the
    /// photo's pixel size, the crop taken from it, and the zoom the person had
    /// pinched to. The crop mapping assumes an aspect-filled preview of the same
    /// field of view as the photo, which is one of the things this description
    /// exists to check on a device.
    struct CapturedFrame {
        let image: UIImage
        let description: String
    }

    /// The photo, cropped to the frame when the crop can be mapped and whole when
    /// it cannot. A crop that fails is not a reason to lose the one
    /// full-resolution look at the label: that used to throw, and with live
    /// evidence on hand the throw was swallowed and the capture silently skipped.
    func captureCroppedPhoto() async throws -> CapturedFrame {
        guard let scanner else { throw ScannerError.scannerUnavailable }
        let image = try await scanner.capturePhoto()
        let viewSize = scanner.view.bounds.size
        let visibleRect = scanner.regionOfInterest ?? scanner.view.bounds
        let zoom = scanner.zoomFactor
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let sourceRect = AspectFillCropMapper.sourceRect(
            imageSize: image.size,
            displayedIn: viewSize,
            visibleRect: visibleRect
        )
        if let sourceRect, let cropped = image.cropped(to: sourceRect) {
            let description = String(
                format: "photo %.0f×%.0f px, crop %.0f×%.0f at (%.0f, %.0f), zoom %.1f×",
                pixels.width, pixels.height,
                sourceRect.width * image.scale, sourceRect.height * image.scale,
                sourceRect.minX * image.scale, sourceRect.minY * image.scale,
                zoom
            )
            return CapturedFrame(image: cropped, description: description)
        }
        let description = String(
            format: "photo %.0f×%.0f px, read whole (crop could not be mapped), zoom %.1f×",
            pixels.width, pixels.height, zoom
        )
        return CapturedFrame(image: image, description: description)
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
    /// The drawn frame, in this view's coordinates, measured by the screen that
    /// draws it. Zero until it has been measured.
    let regionOfInterest: CGRect
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

        /// The measured outline when the screen has measured it; the layout's
        /// default proportions until then, so the first frames are not read
        /// edge to edge.
        func configureRegion(for scanner: DataScannerViewController) {
            let measured = parent.regionOfInterest.intersection(scanner.view.bounds)
            let region = measured.isNull || measured.isEmpty
                ? ScanFrameLayout.region(in: scanner.view.bounds)
                : measured
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
    /// The evidence a pass over an image produced, and what it took to get it,
    /// in the words the capture note on the review screen shows.
    struct Result {
        let evidence: [ScanEvidence]
        let report: String
    }

    private struct Line {
        let text: String
        let confidence: Double
        /// Normalized to the whole upright image, the way Vision reports it:
        /// origin at the bottom left.
        let box: CGRect
    }

    /// Text sizes Vision reads comfortably start around this many pixels tall; a
    /// smaller line is scaled up to it before its second reading.
    private static let comfortableLineHeight: CGFloat = 40
    private static let maximumRegionPasses = 5
    /// A frame smaller than this on its short side was already read at a size
    /// Vision handles whole, so tiling it would only cost time.
    private static let minimumTiledDimension: CGFloat = 1500

    static func recognize(data: Data, origin: ScanEvidence.Origin) async throws -> [ScanEvidence] {
        guard let image = UIImage(data: data) else { throw ScannerError.unreadableImage }
        return try await recognizeWithReport(image: image, origin: origin).evidence
    }

    static func recognize(image: UIImage, origin: ScanEvidence.Origin) async throws -> [ScanEvidence] {
        try await recognizeWithReport(image: image, origin: origin).evidence
    }

    static func recognizeWithReport(image: UIImage, origin: ScanEvidence.Origin) async throws -> Result {
        guard let upright = image.uprightCGImage() else { throw ScannerError.unreadableImage }
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try recognize(upright: upright, origin: origin))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// One reading of the whole image, then a second look for the one line that
    /// is routinely too small for the first: the NDC.
    ///
    /// Vision works the whole frame at a bounded resolution, so on a
    /// twelve-megapixel photo a two-millimetre line of print is handed to the
    /// recognizer a few pixels tall, whatever `minimumTextHeight` says. Every
    /// line that looks like it might be the code's — the caption, or digits with
    /// hyphens — is cut out of the full-resolution image, scaled up, and read
    /// again with language correction off, because correction is built for
    /// words and a code is not a word. If nothing looked like the code at all,
    /// or nothing read so far names a listed product, the frame is read in tiles
    /// at full resolution as well. Only code-bearing lines come back from the
    /// second look; the rest of the label was already read the first time.
    ///
    /// The second look runs whether or not the first pass read a code, because a
    /// slightly blurred line is not left unread, it is misread: a 6 as a 5, a 4
    /// as a 0, and the result is a well-formed code that names nothing or,
    /// worse, a neighbouring product. Neither pass is right every time, so when
    /// the two read different codes both go forward and the identification gate
    /// keeps the one the label vouches for.
    ///
    /// When even that reads no listed code the label accepts, the code's line
    /// is read at a spread of sizes and Vision's lower-ranked guesses are
    /// consulted, under a stricter rule than any top reading faces: see
    /// `alternateCodeLines`. On iOS 27 a shaken code line comes back with its
    /// sixes read as fives at almost every size, and the right code turns up
    /// only among the guesses below the top.
    private static func recognize(upright: CGImage, origin: ScanEvidence.Origin) throws -> Result {
        let handler = VNImageRequestHandler(cgImage: upright, orientation: .up, options: [:])
        let textRequest = makeTextRequest(languageCorrection: true)
        try handler.perform([textRequest])
        // Barcode inference is optional and can be unavailable even when OCR succeeds.
        // Never discard usable medication text because a code model could not initialize.
        let barcodeRequest = VNDetectBarcodesRequest()
        try? handler.perform([barcodeRequest])
        let observations = textRequest.results ?? []
        let barcodes = barcodeRequest.results ?? []

        var lines = observations.compactMap(line(from:))
        var report = "read \(lines.count) lines and \(barcodes.count) codes"

        // Judged on the lines read together, in order: a code split around its
        // hyphen onto a second line is a code once the lines are joined, and
        // does not need the second look.
        let readTogether = sorted(lines).map(\.text).joined(separator: "\n")
        var readings = NationalDrugCode.readings(inLabelText: readTogether)
        if !readings.isEmpty, !resolvesInDirectory(readings) {
            report += "; the code read is not listed"
        }
        let suspects = observations
            .filter { observation in
                observation.topCandidates(1).first.map { looksLikeCodeFragment($0.string) } ?? false
            }
            .sorted { $0.boundingBox.height > $1.boundingBox.height }
            .prefix(maximumRegionPasses)
        var found: [Line] = []
        for suspect in suspects {
            found += zoomedCodeLines(around: suspect.boundingBox, in: upright)
        }
        report += "; zoomed \(suspects.count.counted("line", plural: "lines")) for the NDC, found \(found.count)"
        readings += found.flatMap { NationalDrugCode.readings(inLabelText: $0.text) }
        if !resolvesInDirectory(readings) {
            let tiled = tiledCodeLines(in: upright)
            found += tiled
            report += tiled.isEmpty ? "; tiling found none" : "; tiling found \(tiled.count)"
            readings += tiled.flatMap { NationalDrugCode.readings(inLabelText: $0.text) }
        }
        var regions: [CGRect] = []
        for box in suspects.map(\.boundingBox) + found.map(\.box)
            where !regions.contains(where: { overlap($0, box) > 0.5 }) {
            regions.append(box)
        }
        var guessed: [Line] = []
        if !regions.isEmpty,
           let judge = judgeForAlternates(label: makeEvidence(lines: lines, barcodes: barcodes, origin: origin), codesRead: readings) {
            guessed = alternateCodeLines(around: regions, in: upright, vouchedFor: judge.namesExactly)
            report += "; the label vouched for \(guessed.count.counted("alternate reading", plural: "alternate readings"))"
        }
        var codesRead = Set(NationalDrugCode.readings(inLabelText: readTogether).map(\.raw))
        for line in found {
            // The same code read again adds nothing. A different one goes
            // forward beside the first pass's line: the first pass's
            // misreading of non-code print gives way to the zoomed reading, but
            // a code-bearing line keeps its place, and the identification gate
            // decides between the two codes with the label's help.
            let codes = NationalDrugCode.readings(inLabelText: line.text).map(\.raw)
            guard !codes.isEmpty, !Set(codes).isSubset(of: codesRead) else { continue }
            codesRead.formUnion(codes)
            lines.removeAll { !carriesCode($0) && overlap($0.box, line.box) > 0.5 }
            lines.append(line)
        }
        // A guess brings its code and displaces nothing. The rest of a guess
        // is the recognizer's second thoughts about print the passes already
        // read, a quantity or a date among it, and never outranks their
        // reading of it.
        for line in guessed {
            let codes = NationalDrugCode.readings(inLabelText: line.text).map(\.raw)
            guard !codes.isEmpty, !Set(codes).isSubset(of: codesRead) else { continue }
            codesRead.formUnion(codes)
            lines.append(line)
        }

        return Result(evidence: makeEvidence(lines: lines, barcodes: barcodes, origin: origin), report: report)
    }

    /// Whether any candidate of the reading names a listed product. With no
    /// directory at hand, any well-formed code counts, as before.
    private static func resolvesInDirectory(_ readings: [NDCReading]) -> Bool {
        readings.contains(where: resolvesInDirectory)
    }

    private static func resolvesInDirectory(_ reading: NDCReading) -> Bool {
        let directory = NDCDirectory.shared
        guard !directory.isEmpty else { return true }
        return reading.candidates.contains { directory.product(for: $0) != nil }
    }

    private static func makeTextRequest(languageCorrection: Bool) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = languageCorrection
        // Match the live scanner's language set so a photo of the same label
        // reads the same way the camera does.
        request.recognitionLanguages = ["en-US", "es-ES", "fr-FR"]
        return request
    }

    private static func line(from observation: VNRecognizedTextObservation) -> Line? {
        guard let candidate = observation.topCandidates(3).first(where: {
            $0.confidence >= 0.25 && LabelTextPolicy.sanitized($0.string) != nil
        }), let value = LabelTextPolicy.sanitized(candidate.string) else { return nil }
        return Line(text: value, confidence: Double(candidate.confidence), box: observation.boundingBox)
    }

    private static func carriesCode(_ line: Line) -> Bool {
        !NationalDrugCode.readings(inLabelText: line.text).isEmpty
    }

    /// The caption, or digits broken by hyphens the way a code is. Small print
    /// turns "NDC" into "N0C" or "NOC" often enough that those count.
    private static let codeFragmentPattern =
        /(?i)\bN\s?[D0O]\s?C\b|[0-9OIl]{4,5}\s?-\s?[0-9OIl]{3,4}|(?:^|[^0-9A-Za-z])[0-9OIl]{8,11}(?![0-9A-Za-z])/

    static func looksLikeCodeFragment(_ text: String) -> Bool {
        text.firstMatch(of: codeFragmentPattern) != nil
    }

    /// A code-bearing line the second pass read, as plain values for the tests
    /// that exercise the crop, the scaling and the mapping back.
    struct CodeLine: Equatable {
        let text: String
        let box: CGRect
    }

    static func zoomedCodeReadings(around box: CGRect, in image: CGImage) -> [CodeLine] {
        zoomedCodeLines(around: box, in: image).map { CodeLine(text: $0.text, box: $0.box) }
    }

    static func tiledCodeReadings(in image: CGImage) -> [CodeLine] {
        tiledCodeLines(in: image).map { CodeLine(text: $0.text, box: $0.box) }
    }

    static func alternateCodeReadings(around boxes: [CGRect], in image: CGImage, label: [ScanEvidence]) -> [CodeLine] {
        guard let judge = LabelJudge(label: label) else { return [] }
        return alternateCodeLines(around: boxes, in: image, vouchedFor: judge.namesExactly).map { CodeLine(text: $0.text, box: $0.box) }
    }

    static func wouldLookForAlternates(label: [ScanEvidence], codesRead: [NDCReading]) -> Bool {
        judgeForAlternates(label: label, codesRead: codesRead) != nil
    }

    /// The judge for a search of lower-ranked guesses, or nil when there is no
    /// call for one. A listed code the label does not contradict ends it,
    /// printed or in a barcode: a barcode needs no guess beside it, and a
    /// guess at another product would only leave the gate two to choose
    /// between. A code the label contradicts does not end it: the same drug
    /// at its other strength is just what a shaken line is misread as.
    private static func judgeForAlternates(label: [ScanEvidence], codesRead: [NDCReading]) -> LabelJudge? {
        guard let judge = LabelJudge(label: label) else { return nil }
        let everyCode = codesRead + NDCIdentification.readings(in: label)
        return everyCode.contains(where: judge.settles) ? nil : judge
    }

    /// Cuts the line out of the full-resolution image with room on every side —
    /// the code often runs on past the box the first pass drew — scales it up to
    /// a size Vision reads well, and reads it again without language correction.
    private static func zoomedCodeLines(around box: CGRect, in image: CGImage) -> [Line] {
        guard let (crop, region, lineHeight) = lineCrop(around: box, in: image) else { return [] }
        let scale = min(4, max(2, comfortableLineHeight / max(lineHeight, 1)))
        guard let scaled = crop.scaled(by: scale) else { return [] }
        return codeLines(in: scaled, region: region, imageSize: CGSize(width: image.width, height: image.height))
    }

    /// The line cut out of the full-resolution image with room on every side,
    /// where it sits in the image, and how many pixels tall the line is.
    private static func lineCrop(around box: CGRect, in image: CGImage) -> (CGImage, CGRect, CGFloat)? {
        let imageSize = CGSize(width: image.width, height: image.height)
        let pixelRect = pixelRect(fromNormalized: box, imageSize: imageSize)
        let padX = max(pixelRect.height * 2, pixelRect.width * 0.25)
        let padY = pixelRect.height * 0.8
        let region = pixelRect
            .insetBy(dx: -padX, dy: -padY)
            .intersection(CGRect(origin: .zero, size: imageSize))
            .integral
        guard !region.isNull, region.width >= 8, region.height >= 8,
              let crop = image.cropping(to: region) else { return nil }
        return (crop, region, pixelRect.height)
    }

    /// Reads the image in overlapping tiles at full resolution. A fallback for a
    /// frame whose first pass produced nothing that even looked like the code.
    ///
    /// A tile finds the line; the zoomed look reads it again. The tile hands
    /// Vision small print at its own few pixels, and iOS 27 reads the last
    /// digit of such a line wrong ("-07" for "-02") where the zoom reads it
    /// right, so the zoom's reading leads. But the zoom misreads a shaken line
    /// too, so when the tile read a code the zoom did not, both go forward, as
    /// the first pass's does beside the zoom's: the identification gate asks
    /// the label between two products, and a package read two ways is left
    /// off the code rather than guessed.
    private static func tiledCodeLines(in image: CGImage) -> [Line] {
        let imageSize = CGSize(width: image.width, height: image.height)
        guard min(imageSize.width, imageSize.height) >= minimumTiledDimension else { return [] }
        let columns = imageSize.width >= imageSize.height ? 3 : 2
        let rows = imageSize.width >= imageSize.height ? 2 : 3
        let tileOverlap: CGFloat = 0.15
        let stepX = imageSize.width / CGFloat(columns)
        let stepY = imageSize.height / CGFloat(rows)
        var found: [Line] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let tile = CGRect(
                    x: CGFloat(column) * stepX,
                    y: CGFloat(row) * stepY,
                    width: stepX * (1 + tileOverlap),
                    height: stepY * (1 + tileOverlap)
                )
                .intersection(CGRect(origin: .zero, size: imageSize))
                .integral
                guard !tile.isNull, let crop = image.cropping(to: tile) else { continue }
                for line in codeLines(in: crop, region: tile, imageSize: imageSize)
                    where !found.contains(where: { overlap($0.box, line.box) > 0.5 }) {
                    found.append(line)
                }
            }
        }
        func codes(_ line: Line) -> Set<String> {
            Set(NationalDrugCode.readings(inLabelText: line.text).map(\.raw))
        }
        var read: [Line] = []
        for line in found {
            let zoomed = zoomedCodeLines(around: line.box, in: image)
            let tileReadMore = zoomed.isEmpty
                || !codes(line).isSubset(of: zoomed.reduce(into: Set<String>()) { $0.formUnion(codes($1)) })
            // Overlapping tiles find one line twice; the same codes on the
            // same line are one reading.
            for reading in tileReadMore ? zoomed + [line] : zoomed
                where !read.contains(where: { overlap($0.box, reading.box) > 0.5 && codes($0) == codes(reading) }) {
                read.append(reading)
            }
        }
        return read
    }

    /// The label, read the ordinary way, as the judge of codes the passes did
    /// not read outright. Nil when it could vouch for none, because it shows
    /// no confirmed name or no strength, which spares looks that could only
    /// come back empty.
    private struct LabelJudge {
        let draft: MedicationDraft
        let labelText: String
        let directory: NDCDirectory

        init?(label: [ScanEvidence], directory: NDCDirectory = .shared) {
            guard !directory.isEmpty else { return nil }
            let draft = MedicationLabelInterpreter.offlineDraft(label, ndcDirectory: directory)
            guard draft.nameProvenance == .vocabulary || draft.nameProvenance == .strengthAnchored,
                  !draft.name.isEmpty, !draft.strength.isEmpty else { return nil }
            self.draft = draft
            labelText = LabelCandidateBuilder.textLines(from: draft.evidence).joined(separator: "\n")
            self.directory = directory
        }

        /// A reading of a listed product the label does not contradict, which
        /// the identification gate will take as it stands.
        func settles(_ reading: NDCReading) -> Bool {
            reading.candidates.contains { code in
                guard let product = directory.product(for: code) else { return false }
                let match = NDCIdentification.Match(code: code, product: product, source: reading.source)
                return NDCIdentification.verdict(for: match, against: draft, labelText: labelText) != .contradicted
            }
        }

        /// See `NDCIdentification.labelNamesExactly`.
        func namesExactly(_ code: NationalDrugCode) -> Bool {
            guard let product = directory.product(for: code) else { return false }
            let match = NDCIdentification.Match(code: code, product: product, source: .printedText)
            return NDCIdentification.labelNamesExactly(match, draft: draft, labelText: labelText, directory: directory)
        }
    }

    /// Text heights, in pixels, a code line is read at when looking for guesses
    /// below Vision's top one. Where a shaken line reads right is close to
    /// chance, a matter of how its blurred edges land on the pixel grid, so it
    /// is read at a spread of sizes rather than at one.
    private static let alternateLookHeights: [CGFloat] = [40, 50, 60, 80, 100, 120, 150]
    /// Every look is a full recognition, so only the likeliest lines are
    /// looked at, and only when nothing read is a code the label accepts.
    private static let maximumAlternateRegions = 2

    /// Vision's lower-ranked readings of each region's code line, as the code
    /// alone, kept only when the label itself names the product it resolves to.
    ///
    /// A guess below the top one is a guess among guesses, and the likeliest
    /// wrong one is a neighbouring code of the same labeler: the same drug at
    /// another strength, or another release of it at the same strength. On a
    /// shaken Tecfidera 240 mg line, the 120 mg code turned up among the
    /// guesses more often than the right one. So a guess must clear more than a
    /// top reading does: the label must name the product exactly, by its name,
    /// strength, and any form or brand it prints, and must fit none of the
    /// labeler's other products as well (see
    /// `NDCIdentification.labelNamesExactly`). Only then does the code go
    /// forward, where the ordinary gate judges it again beside everything else
    /// read, and two products surviving is still no answer. Only language
    /// correction offers ranked guesses, so these looks leave it on; the
    /// directory judges the code, not it.
    private static func alternateCodeLines(
        around boxes: [CGRect],
        in image: CGImage,
        vouchedFor judge: (NationalDrugCode) -> Bool
    ) -> [Line] {
        let imageSize = CGSize(width: image.width, height: image.height)
        var found: [Line] = []
        var codesKept: Set<String> = []
        // The same product turns up in guess after guess, and judging it reads
        // every listing of its labeler.
        var judged: [String: Bool] = [:]
        func vouched(_ code: NationalDrugCode) -> Bool {
            if let known = judged[code.productKey] { return known }
            let answer = judge(code)
            judged[code.productKey] = answer
            return answer
        }
        for box in boxes.prefix(maximumAlternateRegions) {
            guard let (crop, region, lineHeight) = lineCrop(around: box, in: image) else { continue }
            for height in alternateLookHeights {
                let scale = min(8, max(0.5, height / max(lineHeight, 1)))
                guard let scaled = crop.scaled(by: scale) else { continue }
                let handler = VNImageRequestHandler(cgImage: scaled, orientation: .up, options: [:])
                let request = makeTextRequest(languageCorrection: true)
                try? handler.perform([request])
                for observation in request.results ?? [] {
                    for candidate in observation.topCandidates(10) {
                        guard let value = LabelTextPolicy.sanitized(candidate.string) else { continue }
                        for reading in NationalDrugCode.readings(inLabelText: value)
                            where reading.candidates.contains(where: vouched) && codesKept.insert(reading.raw).inserted {
                            // Only the code the label vouched for goes forward.
                            found.append(Line(
                                text: "NDC \(reading.raw)",
                                confidence: Double(candidate.confidence),
                                box: fullImageBox(fromCropBox: observation.boundingBox, cropRect: region, imageSize: imageSize)
                            ))
                        }
                    }
                }
            }
        }
        return found
    }

    /// The code-bearing lines in a crop, with their boxes mapped back onto the
    /// whole image. A reading that carries a code is kept at a lower confidence
    /// than the first pass demands: the identification gate still requires the
    /// label to vouch for it.
    private static func codeLines(in crop: CGImage, region: CGRect, imageSize: CGSize) -> [Line] {
        let handler = VNImageRequestHandler(cgImage: crop, orientation: .up, options: [:])
        let request = makeTextRequest(languageCorrection: false)
        try? handler.perform([request])
        return (request.results ?? []).compactMap { observation -> Line? in
            guard let candidate = observation.topCandidates(3).first(where: {
                $0.confidence >= 0.1 && !NationalDrugCode.readings(inLabelText: $0.string).isEmpty
            }), let value = LabelTextPolicy.sanitized(candidate.string) else { return nil }
            return Line(
                text: value,
                confidence: Double(candidate.confidence),
                box: fullImageBox(fromCropBox: observation.boundingBox, cropRect: region, imageSize: imageSize)
            )
        }
    }

    /// Vision's normalized box, with its bottom-left origin, as pixels from the
    /// top left of the image.
    static func pixelRect(fromNormalized box: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: box.minX * imageSize.width,
            y: (1 - box.maxY) * imageSize.height,
            width: box.width * imageSize.width,
            height: box.height * imageSize.height
        )
    }

    /// A box Vision reported inside a crop, as the same normalized box on the
    /// whole image. Scaling the crop before reading it does not move its
    /// normalized coordinates, so only the crop's place in the image matters.
    static func fullImageBox(fromCropBox box: CGRect, cropRect: CGRect, imageSize: CGSize) -> CGRect {
        let bottomInPixels = cropRect.maxY - box.minY * cropRect.height
        return CGRect(
            x: (cropRect.minX + box.minX * cropRect.width) / imageSize.width,
            y: 1 - bottomInPixels / imageSize.height,
            width: box.width * cropRect.width / imageSize.width,
            height: box.height * cropRect.height / imageSize.height
        )
    }

    /// How much of the smaller box the two share.
    private static func overlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let shared = lhs.intersection(rhs)
        guard !shared.isNull, !shared.isEmpty else { return 0 }
        let smaller = min(lhs.width * lhs.height, rhs.width * rhs.height)
        guard smaller > 0 else { return 0 }
        return (shared.width * shared.height) / smaller
    }

    /// Reading order: top to bottom, left to right within a row.
    private static func sorted(_ lines: [Line]) -> [Line] {
        lines.sorted { lhs, rhs in
            if abs(lhs.box.midY - rhs.box.midY) > 0.02 {
                return lhs.box.midY > rhs.box.midY
            }
            return lhs.box.minX < rhs.box.minX
        }
    }

    private static func makeEvidence(
        lines: [Line],
        barcodes: [VNBarcodeObservation],
        origin: ScanEvidence.Origin
    ) -> [ScanEvidence] {
        let captureID = UUID()
        var evidence = sorted(lines).enumerated().map { index, line in
            ScanEvidence(
                kind: .text,
                value: line.text,
                confidence: line.confidence,
                origin: origin,
                captureID: captureID,
                lineIndex: index
            )
        }
        evidence.append(contentsOf: barcodes.compactMap { observation in
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

private extension UIImage {
    /// The pixels with the orientation baked in, so a box Vision reports maps
    /// straight onto them when a line is cut out for its second reading. A camera
    /// photo is stored sideways with a flag; only that case costs a redraw.
    func uprightCGImage() -> CGImage? {
        guard let cgImage else { return nil }
        if imageOrientation == .up, scale == 1 { return cgImage }
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        guard pixelSize.width >= 1, pixelSize.height >= 1 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: pixelSize))
        }.cgImage
    }
}

private extension CGImage {
    func scaled(by factor: CGFloat) -> CGImage? {
        let newWidth = Int((CGFloat(width) * factor).rounded())
        let newHeight = Int((CGFloat(height) * factor).rounded())
        guard newWidth > 0, newHeight > 0,
              let context = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
              ) else { return nil }
        context.interpolationQuality = .high
        context.draw(self, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }
}
