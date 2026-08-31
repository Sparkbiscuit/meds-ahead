import Foundation

enum LabelTextPolicy {
    private static let minimumVisibleCharacterCount = 2

    /// Returns only label lines that contain Latin-script text or useful ASCII
    /// numbers. A mixed line containing any non-Latin letter is rejected rather
    /// than transliterated, so invented Cyrillic or Han fragments never become
    /// medication evidence. Spanish and French diacritics remain intact.
    static func sanitized(_ value: String) -> String? {
        let lines = value
            .components(separatedBy: .newlines)
            .map { $0.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter(isAllowedLine)
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    static func isAllowedLine(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumVisibleCharacterCount else { return false }

        var hasLatinLetter = false
        var hasDigit = false
        for scalar in trimmed.decomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
                guard isLatinLetter(scalar) else { return false }
                hasLatinLetter = true
            case .decimalNumber:
                hasDigit = true
            case .control, .format, .surrogate, .privateUse, .unassigned:
                return false
            default:
                continue
            }
        }
        return hasLatinLetter || hasDigit
    }

    private static func isLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0041...0x005A, 0x0061...0x007A,
             0x00C0...0x00D6, 0x00D8...0x00F6, 0x00F8...0x02AF,
             0x1D00...0x1DBF, 0x1E00...0x1EFF, 0x2C60...0x2C7F,
             0xA720...0xA7FF, 0xAB30...0xAB6F,
             0xFF21...0xFF3A, 0xFF41...0xFF5A:
            true
        default:
            false
        }
    }
}

/// The handful of facts the live scanner overlay shows while the camera is up.
///
/// Deriving these runs the whole parse pipeline, including a match against the
/// bundled 12,865-entry vocabulary, so it must never be computed inside a
/// SwiftUI body. `ScannerScreen` recomputes it off the main actor, debounced,
/// and stores the result.
struct ScanPreview: Equatable, Sendable {
    var medicationName = ""
    var hasStrength = false
    var hasQuantity = false
    var hasProductIdentifier = false
    var hasRefills = false

    var hasUsefulProgress: Bool {
        !medicationName.isEmpty || hasStrength || hasQuantity || hasProductIdentifier || hasRefills
    }

    /// One pass over the pipeline. `offlineDraft` already begins from a full
    /// `ScanParser.parse`, so every field here comes from that single run.
    static func make(from evidence: [ScanEvidence]) -> ScanPreview {
        guard !evidence.isEmpty else { return ScanPreview() }
        let draft = MedicationLabelInterpreter.offlineDraft(evidence)
        return ScanPreview(
            medicationName: draft.name,
            hasStrength: !draft.strength.isEmpty,
            hasQuantity: draft.currentSupply != nil,
            hasProductIdentifier: !draft.productIdentifier.isEmpty,
            hasRefills: draft.refillsRemaining != nil
        )
    }
}

struct LiveEvidenceObservation<ID: Hashable> {
    let id: ID
    let evidence: ScanEvidence
}

struct LiveEvidenceUpdate {
    let evidence: [ScanEvidence]
    let promotedNewEvidence: Bool
}

/// Keeps live VisionKit observations ephemeral until the same recognized item
/// remains coherent long enough to trust. Once promoted, a line survives bottle
/// rotation, but a better reading of the same item replaces it instead of being
/// appended as a second fact.
struct LiveEvidenceTracker<ID: Hashable> {
    private struct Track {
        var evidence: ScanEvidence
        var stableSince: TimeInterval
        var promoted: Bool
    }

    private var tracks: [ID: Track] = [:]
    private var retainedEvidence: [ScanEvidence] = []
    private let textStabilityInterval: TimeInterval
    private let barcodeStabilityInterval: TimeInterval

    init(
        textStabilityInterval: TimeInterval = 0.40,
        barcodeStabilityInterval: TimeInterval = 0.15
    ) {
        self.textStabilityInterval = textStabilityInterval
        self.barcodeStabilityInterval = barcodeStabilityInterval
    }

    mutating func update(
        _ observations: [LiveEvidenceObservation<ID>],
        at timestamp: TimeInterval
    ) -> LiveEvidenceUpdate {
        var promotedEvidenceChanged = false
        let visibleIDs = Set(observations.map(\.id))
        for id in Array(tracks.keys) where !visibleIDs.contains(id) {
            if let track = tracks[id], track.promoted {
                retainedEvidence = ScanEvidenceQuality.mergingBest(
                    existing: retainedEvidence,
                    additions: [track.evidence]
                )
            }
            tracks.removeValue(forKey: id)
        }

        for observation in observations {
            guard let evidence = ScanEvidenceQuality.sanitized(observation.evidence) else {
                tracks.removeValue(forKey: observation.id)
                continue
            }

            if var track = tracks[observation.id],
               ScanEvidenceQuality.isEquivalentReading(track.evidence, evidence) {
                let preferred = ScanEvidenceQuality.preferred(track.evidence, evidence)
                if track.promoted, preferred != track.evidence { promotedEvidenceChanged = true }
                track.evidence = preferred
                tracks[observation.id] = track
            } else {
                tracks[observation.id] = Track(
                    evidence: evidence,
                    stableSince: timestamp,
                    promoted: false
                )
            }
        }
        let update = promote(at: timestamp)
        return LiveEvidenceUpdate(
            evidence: update.evidence,
            promotedNewEvidence: update.promotedNewEvidence || promotedEvidenceChanged
        )
    }

    mutating func promote(at timestamp: TimeInterval) -> LiveEvidenceUpdate {
        var promotedNewEvidence = false
        for id in Array(tracks.keys) {
            guard var track = tracks[id], !track.promoted else { continue }
            let requiredInterval = track.evidence.kind == .barcode
                ? barcodeStabilityInterval
                : textStabilityInterval
            guard timestamp - track.stableSince >= requiredInterval else { continue }
            track.promoted = true
            tracks[id] = track
            promotedNewEvidence = true
        }

        let activeEvidence = tracks.values.compactMap { $0.promoted ? $0.evidence : nil }
        let evidence = ScanEvidenceQuality.mergingBest(
            existing: retainedEvidence,
            additions: activeEvidence
        )
        return LiveEvidenceUpdate(evidence: evidence, promotedNewEvidence: promotedNewEvidence)
    }

    mutating func reset() {
        tracks.removeAll()
        retainedEvidence.removeAll()
    }
}

enum ScanFrameLayout {
    static let horizontalInset: CGFloat = 24
    static let verticalInset: CGFloat = 64

    static func region(in bounds: CGRect) -> CGRect {
        bounds.insetBy(dx: horizontalInset, dy: verticalInset)
    }
}

enum AspectFillCropMapper {
    static func sourceRect(
        imageSize: CGSize,
        displayedIn viewSize: CGSize,
        visibleRect: CGRect
    ) -> CGRect? {
        guard imageSize.width > 0, imageSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return nil }

        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let displayedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let displayedOrigin = CGPoint(
            x: (viewSize.width - displayedSize.width) / 2,
            y: (viewSize.height - displayedSize.height) / 2
        )
        var sourceRect = CGRect(
            x: (visibleRect.minX - displayedOrigin.x) / scale,
            y: (visibleRect.minY - displayedOrigin.y) / scale,
            width: visibleRect.width / scale,
            height: visibleRect.height / scale
        )
        sourceRect = sourceRect.intersection(CGRect(origin: .zero, size: imageSize))
        return sourceRect.isNull || sourceRect.isEmpty ? nil : sourceRect.integral
    }
}
