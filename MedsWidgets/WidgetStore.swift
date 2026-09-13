import Foundation
import OSLog
import SwiftData

/// The widgets' view of the shared store: opened only when it exists.
///
/// Opening a SwiftData container creates a store where there is none, and an
/// empty store at the shared location would tell the app on its next launch
/// that the move from the legacy location had already happened. So a widget
/// never creates the store; until the app has opened it once, the widgets say
/// to open the app.
enum WidgetStore {
    enum Failure: Error {
        case groupContainerUnavailable
        case notYetShared
    }

    struct Contents {
        /// A fetched model is only alive while its container is: the first
        /// widget build let the container go out of scope on return and every
        /// later property read trapped inside SwiftData. The contents keep it.
        let container: ModelContainer
        let medications: [Medication]
        let schedules: [DoseSchedule]
        let doseEvents: [DoseEvent]
        let inventoryEvents: [InventoryEvent]
    }

    static let schema = Schema([
        Medication.self,
        DoseSchedule.self,
        DoseEvent.self,
        InventoryEvent.self
    ])

    static let log = Logger(subsystem: "com.christoforakis.Meds", category: "widgets")

    static func container() throws -> ModelContainer {
        guard let url = StoreLocation.sharedURL else { throw Failure.groupContainerUnavailable }
        guard FileManager.default.fileExists(atPath: url.path) else { throw Failure.notYetShared }
        let configuration = ModelConfiguration("Meds", schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    static func load() throws -> Contents {
        let container = try container()
        let context = container.mainContext
        let contents = Contents(
            container: container,
            medications: try context.fetch(FetchDescriptor<Medication>()),
            schedules: try context.fetch(FetchDescriptor<DoseSchedule>()),
            doseEvents: try context.fetch(FetchDescriptor<DoseEvent>()),
            inventoryEvents: try context.fetch(FetchDescriptor<InventoryEvent>())
        )
        log.info("loaded \(contents.medications.count) medications, \(contents.schedules.count) schedules, \(contents.doseEvents.count) dose events")
        return contents
    }
}
