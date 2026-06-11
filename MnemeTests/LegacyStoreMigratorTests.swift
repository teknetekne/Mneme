import XCTest
import CoreData
@testable import Mneme

final class LegacyStoreMigratorTests: XCTestCase {
    func testImportDumpPreservesDailyHealthStats() async throws {
        let container = NSPersistentCloudKitContainer(name: "Mneme")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            XCTAssertNil(error)
        }

        let id = UUID()
        let date = Date()
        let dump = LegacyStoreMigrator.DataDump(
            parsedEntries: [],
            workSessions: [],
            variables: [],
            reminderTags: [],
            calorieCache: [],
            currencySettings: [],
            userProfiles: [],
            dailyHealthStats: [
                LegacyStoreMigrator.LegacyDailyHealthStat(
                    id: id,
                    date: date,
                    activeEnergyBurned: 420,
                    stepCount: 8_500,
                    distanceWalkingRunning: 6_200,
                    createdAt: date,
                    modifiedAt: date
                )
            ]
        )

        try await LegacyStoreMigrator.importDump(dump, into: container)

        let request: NSFetchRequest<DailyHealthStat> = DailyHealthStat.fetchRequest()
        let stats = try container.viewContext.fetch(request)
        let stat = try XCTUnwrap(stats.first)
        XCTAssertEqual(stat.id, id)
        XCTAssertEqual(stat.activeEnergyBurned, 420)
        XCTAssertEqual(stat.stepCount, 8_500)
        XCTAssertEqual(stat.distanceWalkingRunning, 6_200)
    }
}
