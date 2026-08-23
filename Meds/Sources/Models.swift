import Foundation
import SwiftData

enum MedicationForm: String, CaseIterable, Codable, Identifiable {
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

enum MedicationSource: String, Codable {
    case scanned
    case manual
}

@Model
final class Medication {
    @Attribute(.unique) var id: UUID
    var name: String
    var nickname: String
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

    init(
        id: UUID = UUID(),
        name: String,
        nickname: String = "",
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
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.nickname = nickname
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
        [name == displayName ? nil : name, strength.isEmpty ? nil : strength]
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

    init(
        id: UUID = UUID(),
        medicationID: UUID,
        scheduleID: UUID? = nil,
        scheduledAt: Date? = nil,
        recordedAt: Date = .now,
        doseQuantity: Double,
        status: DoseEventStatus,
        note: String = ""
    ) {
        self.id = id
        self.medicationID = medicationID
        self.scheduleID = scheduleID
        self.scheduledAt = scheduledAt
        self.recordedAt = recordedAt
        self.doseQuantity = doseQuantity
        self.statusRawValue = status.rawValue
        self.note = note
    }

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

struct MedicationDraft: Equatable {
    var name = ""
    var nickname = ""
    var strength = ""
    var form: MedicationForm = .tablet
    var directions = ""
    var currentSupply: Double?
    var refillsRemaining: Int?
    var expirationDate: Date?
    var lotNumber = ""
    var productIdentifier = ""
    var productIdentifierType = ""
    var source: MedicationSource = .manual
    var overallConfidence = 1.0
    var evidence: [ScanEvidence] = []
}

struct ScanEvidence: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case text
        case barcode
    }

    let id: UUID
    let kind: Kind
    let value: String
    let symbology: String?
    let confidence: Double

    init(
        id: UUID = UUID(),
        kind: Kind,
        value: String,
        symbology: String? = nil,
        confidence: Double = 1
    ) {
        self.id = id
        self.kind = kind
        self.value = value
        self.symbology = symbology
        self.confidence = confidence
    }
}
