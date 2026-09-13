import Foundation
import SwiftData

enum MedicationForm: String, CaseIterable, Codable, Identifiable, Sendable {
    case tablet
    case capsule
    case liquid
    case injection
    case inhaler
    case patch
    case drops
    case topical
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tablet: "Tablet"
        case .capsule: "Capsule"
        case .liquid: "Liquid"
        case .injection: "Injection"
        case .inhaler: "Inhaler"
        case .patch: "Patch"
        case .drops: "Drops"
        case .topical: "Topical"
        case .other: "Other"
        }
    }

    var unitName: String {
        switch self {
        case .tablet: "tablet"
        case .capsule: "capsule"
        case .liquid: "mL"
        case .injection: "dose"
        case .inhaler: "puff"
        case .patch: "patch"
        case .drops: "drop"
        case .topical: "application"
        case .other: "unit"
        }
    }

    var symbolName: String {
        switch self {
        case .tablet, .capsule: "pill.fill"
        case .liquid, .drops: "drop.fill"
        case .injection: "syringe.fill"
        case .inhaler: "lungs.fill"
        case .patch: "cross.case.fill"
        case .topical: "hand.raised.fill"
        case .other: "shippingbox.fill"
        }
    }
}

enum DoseEventStatus: String, Codable {
    case taken
    case skipped
}

enum InventoryReason: String, CaseIterable, Codable, Identifiable {
    case openingCount
    case refill
    case correction
    case lost
    case discarded
    case returned

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openingCount: "Starting count"
        case .refill: "Refill added"
        case .correction: "Count corrected"
        case .lost: "Lost or damaged"
        case .discarded: "Discarded"
        case .returned: "Returned"
        }
    }
}

enum MedicationSource: String, Codable, Sendable {
    case scanned
    case manual
    /// Chosen from the medications a person already tracks in Apple Health.
    case appleHealth
}

/// Where a refill stands once the person has acted on a low-supply warning.
/// The forecast is unchanged by it — the count is the count — but the alarms
/// stop, because the thing they were asking for has been done.
enum RefillStatus: String, Codable, CaseIterable, Sendable {
    case none
    /// Asked the pharmacy or the prescriber; nothing to pick up yet.
    case requested
    /// The pharmacy says it is ready.
    case ready

    var displayName: String {
        switch self {
        case .none: "Not started"
        case .requested: "Requested"
        case .ready: "Ready for pickup"
        }
    }
}

@Model
final class Medication {
    @Attribute(.unique) var id: UUID
    var name: String
    var nickname: String
    var brandName: String = ""
    var strength: String
    var formRawValue: String
    var directions: String
    var notes: String
    var refillsRemaining: Int?
    var refillLeadDays: Int
    var expirationDate: Date?
    var prescriptionExpirationDate: Date?
    var lotNumber: String
    var productIdentifier: String
    var productIdentifierType: String
    var sourceRawValue: String
    var sourceConfidence: Double
    var accentIndex: Int
    var isAsNeeded: Bool
    var remindersEnabled: Bool
    var refillRemindersEnabled: Bool = true
    var detailedNotifications: Bool
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    // Added in 1.1, declared together with inline defaults so a 1.0 store
    // takes them through one lightweight migration, as `brandName` and
    // `countsTowardSupply` did before them.
    /// The pharmacy on the label, for the call a low-supply warning leads to.
    var pharmacyName: String = ""
    var pharmacyPhone: String = ""
    /// The pharmacy's own prescription number, read aloud to the pharmacy.
    var rxNumber: String = ""
    /// Who takes this, in a household where more than one person does.
    var personName: String = ""
    /// The RxNorm concept the medication maps to: Health's own coding for an
    /// imported medication, the bundled table's answer for a scanned NDC. It is
    /// what links a medication here to the same one in Apple Health.
    var rxNormCode: String = ""
    var refillStatusRawValue: String = ""
    /// When the refill was requested, or when it will be ready, by status.
    var refillStatusDate: Date?

    init(
        id: UUID = UUID(),
        name: String,
        nickname: String = "",
        brandName: String = "",
        strength: String = "",
        form: MedicationForm = .tablet,
        directions: String = "",
        notes: String = "",
        refillsRemaining: Int? = nil,
        refillLeadDays: Int = 7,
        expirationDate: Date? = nil,
        prescriptionExpirationDate: Date? = nil,
        lotNumber: String = "",
        productIdentifier: String = "",
        productIdentifierType: String = "",
        source: MedicationSource = .manual,
        sourceConfidence: Double = 1,
        accentIndex: Int = 0,
        isAsNeeded: Bool = false,
        remindersEnabled: Bool = true,
        refillRemindersEnabled: Bool = true,
        detailedNotifications: Bool = false,
        isArchived: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        pharmacyName: String = "",
        pharmacyPhone: String = "",
        rxNumber: String = "",
        personName: String = "",
        rxNormCode: String = "",
        refillStatus: RefillStatus = .none,
        refillStatusDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.nickname = nickname
        self.brandName = brandName
        self.strength = strength
        self.formRawValue = form.rawValue
        self.directions = directions
        self.notes = notes
        self.refillsRemaining = refillsRemaining
        self.refillLeadDays = refillLeadDays
        self.expirationDate = expirationDate
        self.prescriptionExpirationDate = prescriptionExpirationDate
        self.lotNumber = lotNumber
        self.productIdentifier = productIdentifier
        self.productIdentifierType = productIdentifierType
        self.sourceRawValue = source.rawValue
        self.sourceConfidence = sourceConfidence
        self.accentIndex = accentIndex
        self.isAsNeeded = isAsNeeded
        self.remindersEnabled = remindersEnabled
        self.refillRemindersEnabled = refillRemindersEnabled
        self.detailedNotifications = detailedNotifications
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pharmacyName = pharmacyName
        self.pharmacyPhone = pharmacyPhone
        self.rxNumber = rxNumber
        self.personName = personName
        self.rxNormCode = rxNormCode
        self.refillStatusRawValue = refillStatus == .none ? "" : refillStatus.rawValue
        self.refillStatusDate = refillStatusDate
    }

    var refillStatus: RefillStatus {
        get { RefillStatus(rawValue: refillStatusRawValue) ?? .none }
        set { refillStatusRawValue = newValue == .none ? "" : newValue.rawValue }
    }

    /// The RxNorm codes Apple Health may know this medication by. A medication
    /// imported from Health stores its coding as the product identifier; a
    /// scanned one carries the bundled table's answer for its NDC. Empty for a
    /// medication with no exact identity, which is never matched by name.
    var healthMatchingCodes: Set<String> {
        var codes: Set<String> = []
        if !rxNormCode.isEmpty { codes.insert(rxNormCode) }
        if productIdentifierType == "RxNorm", !productIdentifier.isEmpty { codes.insert(productIdentifier) }
        return codes
    }

    var form: MedicationForm {
        get { MedicationForm(rawValue: formRawValue) ?? .other }
        set { formRawValue = newValue.rawValue }
    }

    var source: MedicationSource {
        get { MedicationSource(rawValue: sourceRawValue) ?? .manual }
        set { sourceRawValue = newValue.rawValue }
    }

    var displayName: String { nickname.isEmpty ? name : nickname }
    var subtitle: String {
        [name == displayName ? nil : name, brandName.isEmpty ? nil : "Brand: \(brandName)", strength.isEmpty ? nil : strength]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

@Model
final class DoseSchedule {
    @Attribute(.unique) var id: UUID
    var medicationID: UUID
    var minutesAfterMidnight: Int
    var doseQuantity: Double
    var weekdayMask: Int
    var label: String
    var startDate: Date
    var endDate: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        medicationID: UUID,
        minutesAfterMidnight: Int,
        doseQuantity: Double = 1,
        weekdayMask: Int = 0b1111111,
        label: String = "",
        startDate: Date = .now,
        endDate: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.medicationID = medicationID
        self.minutesAfterMidnight = minutesAfterMidnight
        self.doseQuantity = doseQuantity
        self.weekdayMask = weekdayMask
        self.label = label
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
    }
}

@Model
final class DoseEvent {
    @Attribute(.unique) var id: UUID
    var medicationID: UUID
    var scheduleID: UUID?
    var scheduledAt: Date?
    var recordedAt: Date
    var doseQuantity: Double
    var statusRawValue: String
    var note: String
    /// A dose taken before Meds Ahead was keeping this medication's count —
    /// history imported from Apple Health — is real for the as-needed rate but was
    /// not taken from a count the app was tracking, so it must not charge the
    /// supply the person just entered. Declared with an inline default so existing
    /// stores take it through a lightweight migration, as `brandName` did.
    var countsTowardSupply: Bool = true
    /// The Apple Health sample this event mirrors, when it mirrors one. The
    /// sync skips a sample it has already stored and removes the copy of one
    /// Health has since taken back.
    var healthSampleID: UUID? = nil

    init(
        id: UUID = UUID(),
        medicationID: UUID,
        scheduleID: UUID? = nil,
        scheduledAt: Date? = nil,
        recordedAt: Date = .now,
        doseQuantity: Double,
        status: DoseEventStatus,
        note: String = "",
        countsTowardSupply: Bool = true,
        healthSampleID: UUID? = nil
    ) {
        self.id = id
        self.medicationID = medicationID
        self.scheduleID = scheduleID
        self.scheduledAt = scheduledAt
        self.recordedAt = recordedAt
        self.doseQuantity = doseQuantity
        self.statusRawValue = status.rawValue
        self.note = note
        self.countsTowardSupply = countsTowardSupply
        self.healthSampleID = healthSampleID
    }

    /// The note an imported Health dose carries, so history reads honestly.
    static let appleHealthNote = "Logged in Apple Health"

    var status: DoseEventStatus {
        get { DoseEventStatus(rawValue: statusRawValue) ?? .taken }
        set { statusRawValue = newValue.rawValue }
    }
}

@Model
final class InventoryEvent {
    @Attribute(.unique) var id: UUID
    var medicationID: UUID
    var date: Date
    var delta: Double
    var reasonRawValue: String
    var note: String

    init(
        id: UUID = UUID(),
        medicationID: UUID,
        date: Date = .now,
        delta: Double,
        reason: InventoryReason,
        note: String = ""
    ) {
        self.id = id
        self.medicationID = medicationID
        self.date = date
        self.delta = delta
        self.reasonRawValue = reason.rawValue
        self.note = note
    }

    var reason: InventoryReason {
        get { InventoryReason(rawValue: reasonRawValue) ?? .correction }
        set { reasonRawValue = newValue.rawValue }
    }
}

/// How a scanned medication name was arrived at. A name found on the line that
/// also carries the strength is trustworthy enough to pre-fill for review; a line
/// that merely looked name-shaped is not, and must not reach the name field.
enum MedicationNameProvenance: String, Hashable, Sendable {
    case none
    case soleCandidate
    /// Read from a line next to the one carrying the strength. Weaker than
    /// `strengthAnchored`: a pharmacy address, a manufacturer and a patient name all
    /// sit next to the strength on a real label, so this must be confirmed against
    /// the vocabulary before it may fill the name field.
    case adjacentToStrength
    case strengthAnchored
    case vocabulary
    /// Resolved from the National Drug Code the label carries, printed or in a
    /// barcode, and corroborated by the label. Exact rather than inferred, so it
    /// outranks every reading of the printed name.
    case ndc
    /// The name of a medication the person already tracks in Apple Health, as
    /// they chose or typed it there.
    case appleHealth
}

/// What became of the code a label carried. The review screen says which, so a
/// code that was never read and a code that was read but refused never look
/// the same: only the second is worth checking digit by digit against the bottle.
enum NDCIdentificationOutcome: Hashable, Sendable {
    /// The code resolved, the label vouched for it, and it filled the identity.
    case accepted(code: String)
    /// The code resolved but nothing else on the label backed it up.
    case uncorroborated(code: String, product: String)
    /// The code resolved but the label plainly names something else.
    case contradicted(code: String, product: String)
    /// A code was read that the bundled directory does not list.
    case unlisted(code: String)
    /// The label yielded codes for more than one product.
    case ambiguous

    /// The code as read, for the person to check against the bottle, when it was
    /// read but did not fill anything.
    var codeToCheck: String? {
        switch self {
        case let .uncorroborated(code, _), let .contradicted(code, _), let .unlisted(code):
            code
        case .accepted, .ambiguous:
            nil
        }
    }
}

/// A dose Apple Health logged before the medication existed here.
struct ImportedDose: Hashable, Sendable {
    let date: Date
    let quantity: Double
    /// Health's identifier for the sample, so the ongoing sync recognises the
    /// dose it already imported.
    var sampleID: UUID? = nil
}

struct MedicationDraft: Hashable, Sendable {
    var name = ""
    var nickname = ""
    var brandName = ""
    var strength = ""
    var form: MedicationForm = .tablet
    var directions = ""
    var currentSupply: Double?
    var refillsRemaining: Int?
    var expirationDate: Date?
    var lotNumber = ""
    var productIdentifier = ""
    var productIdentifierType = ""
    var pharmacyName = ""
    var pharmacyPhone = ""
    var rxNumber = ""
    var rxNormCode = ""
    var source: MedicationSource = .manual
    var nameProvenance: MedicationNameProvenance = .none
    var isAsNeeded = false
    /// Recent taken doses Health has on record, offered for import so an
    /// as-needed medication starts with a usage rate instead of a blank one.
    var importedDoses: [ImportedDose] = []
    var overallConfidence = 1.0
    var evidence: [ScanEvidence] = []
    /// What became of the label's NDC, when it carried one.
    var identification: NDCIdentificationOutcome?
    /// What the scanner's Review capture did, for the debug line on the review
    /// screen. Never stored.
    var captureNote = ""
}

struct ScanEvidence: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case text
        case barcode
    }

    enum Origin: String, Hashable, Sendable {
        case unknown
        case liveCamera
        case cameraCapture
        case photoLibrary

        var displayName: String {
            switch self {
            case .unknown: "Recognized"
            case .liveCamera: "Live label"
            case .cameraCapture: "Captured label"
            case .photoLibrary: "Selected photo"
            }
        }
    }

    let id: UUID
    let kind: Kind
    let value: String
    let symbology: String?
    let confidence: Double
    let origin: Origin
    let captureID: UUID?
    let lineIndex: Int?

    init(
        id: UUID = UUID(),
        kind: Kind,
        value: String,
        symbology: String? = nil,
        confidence: Double = 1,
        origin: Origin = .unknown,
        captureID: UUID? = nil,
        lineIndex: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.symbology = symbology
        self.confidence = confidence
        self.origin = origin
        self.captureID = captureID
        self.lineIndex = lineIndex
    }
}
