import PhotosUI
import SwiftUI
import Vision
import VisionKit

struct ScannerScreen: View {
    let onComplete: (MedicationDraft) -> Void
    @State private var evidence: [ScanEvidence] = []
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isProcessingPhoto = false
    @State private var errorMessage: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var canUseLiveScanner: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
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
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            processPhoto(item)
        }
        .alert("Couldn’t Read This Photo", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Try another photo or enter the medication manually.")
        }
    }

    private var scannerArea: some View {
        ZStack {
            if canUseLiveScanner {
                LiveDataScanner(evidence: $evidence)
                    .ignoresSafeArea(edges: .top)
            } else {
                LinearGradient(colors: [.black, Color(red: 0.06, green: 0.11, blue: 0.14)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 14) {
                    Image(systemName: "camera.metering.unknown")
                        .font(.system(size: 48))
                    Text("Live scanning isn’t available here")
                        .font(.title3.weight(.semibold))
                    Text("Choose a clear photo of the label, or use live scanning on a supported iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .foregroundStyle(.white)
            }

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(evidence.isEmpty ? .white.opacity(0.72) : Color.green, style: StrokeStyle(lineWidth: 2, dash: evidence.isEmpty ? [9, 8] : []))
                .padding(.horizontal, 24)
                .padding(.vertical, 64)
                .allowsHitTesting(false)
                .animation(reduceMotion ? nil : .medsSpring, value: evidence.isEmpty)

            VStack {
                HStack {
                    Spacer()
                    if !evidence.isEmpty {
                        Label("\(textCount) text · \(barcodeCount) codes", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                            .foregroundStyle(.white)
                            .padding()
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                Spacer()
                Text(evidence.isEmpty ? "Keep the label inside the frame and slowly rotate the bottle" : "Useful information found — keep rotating for another side")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.48), in: Capsule())
                    .padding(.bottom, 24)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var controls: some View {
        VStack(spacing: 13) {
            if isProcessingPhoto {
                ProgressView("Reading photo…")
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

                Button {
                    let draft = ScanParser.parse(evidence)
                    onComplete(draft)
                } label: {
                    Label("Review", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(evidence.isEmpty || isProcessingPhoto)
            }
            Button("Clear Scan") { evidence.removeAll() }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
                .disabled(evidence.isEmpty)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private var textCount: Int { evidence.filter { $0.kind == .text }.count }
    private var barcodeCount: Int { evidence.filter { $0.kind == .barcode }.count }

    private func processPhoto(_ item: PhotosPickerItem) {
        isProcessingPhoto = true
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ScannerError.unreadableImage
                }
                let found = try await StillImageRecognizer.recognize(data: data)
                await MainActor.run {
                    merge(found)
                    isProcessingPhoto = false
                    if found.isEmpty { errorMessage = "No readable label text or code was found. Try a sharper, wider photo with less glare." }
                }
            } catch {
                await MainActor.run {
                    isProcessingPhoto = false
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
}

private enum ScannerError: Error {
    case unreadableImage
}

private struct LiveDataScanner: UIViewControllerRepresentable {
    @Binding var evidence: [ScanEvidence]

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text(), .barcode()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: LiveDataScanner
        private var liveEvidenceByItemID: [RecognizedItem.ID: ScanEvidence] = [:]
        private var publishedLiveEvidenceIDs: Set<UUID> = []

        init(parent: LiveDataScanner) {
            self.parent = parent
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            merge(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            merge(updatedItems)
        }

        private func merge(_ items: [RecognizedItem]) {
            for item in items {
                let found: ScanEvidence?
                switch item {
                case .text(let text):
                    let confidence = Double(text.observation.topCandidates(1).first?.confidence ?? 0.8)
                    found = ScanEvidence(kind: .text, value: text.transcript, confidence: confidence)
                case .barcode(let barcode):
                    guard let payload = barcode.payloadStringValue, !payload.isEmpty else { continue }
                    found = ScanEvidence(
                        kind: .barcode,
                        value: payload,
                        symbology: barcode.observation.symbology.rawValue,
                        confidence: Double(barcode.observation.confidence)
                    )
                @unknown default:
                    found = nil
                }
                if let found, ScanEvidenceQuality.isUsefulForAutofill(found) {
                    liveEvidenceByItemID[item.id] = found
                } else {
                    liveEvidenceByItemID.removeValue(forKey: item.id)
                }
            }

            let nonLiveEvidence = parent.evidence.filter { !publishedLiveEvidenceIDs.contains($0.id) }
            let currentLiveEvidence = Array(liveEvidenceByItemID.values)
            publishedLiveEvidenceIDs = Set(currentLiveEvidence.map(\.id))
            parent.evidence = ScanEvidenceQuality.mergingBest(
                existing: nonLiveEvidence,
                additions: currentLiveEvidence
            )
        }
    }
}

private enum StillImageRecognizer {
    static func recognize(data: Data) async throws -> [ScanEvidence] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let textRequest = VNRecognizeTextRequest()
                textRequest.recognitionLevel = .accurate
                textRequest.usesLanguageCorrection = true
                let barcodeRequest = VNDetectBarcodesRequest()
                let handler = VNImageRequestHandler(data: data, options: [:])
                do {
                    try handler.perform([textRequest, barcodeRequest])
                    var results: [ScanEvidence] = []
                    for observation in textRequest.results ?? [] {
                        guard let candidate = observation.topCandidates(1).first,
                              candidate.confidence >= 0.30 else { continue }
                        results.append(ScanEvidence(kind: .text, value: candidate.string, confidence: Double(candidate.confidence)))
                    }
                    for observation in barcodeRequest.results ?? [] {
                        guard let payload = observation.payloadStringValue, !payload.isEmpty else { continue }
                        results.append(
                            ScanEvidence(
                                kind: .barcode,
                                value: payload,
                                symbology: observation.symbology.rawValue,
                                confidence: Double(observation.confidence)
                            )
                        )
                    }
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
