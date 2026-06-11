import XCTest
@testable import Mneme

@MainActor
final class EventKitManagerTests: XCTestCase {
    func testCreateEventCommitsLineTagsToCalendarIdentifier() async throws {
        let tagStore = TagStore(persistence: InMemoryPersistence())
        let tagManager = TagManager(tagStore: tagStore)
        let eventKitService = TestEventKitService()
        let manager = EventKitManager(eventKitService: eventKitService, tagManager: tagManager)
        let lineId = UUID()

        try await tagManager.addTag(to: lineId, tagName: "work")
        await waitUntil {
            tagStore.getTags(for: lineId).count == 1
        }

        let result = try await manager.createEvent(
            from: makeEventParsedResult(),
            originalText: "Team sync tomorrow at 3",
            lineId: lineId
        )

        await waitUntil {
            tagStore.getTags(for: lineId).isEmpty && tagStore.getTags(forEventIdentifier: result.identifier).count == 1
        }

        XCTAssertEqual(eventKitService.createEventCallCount, 1)
        XCTAssertEqual(result.identifier, eventKitService.nextEventIdentifier)
        XCTAssertNil(result.tagSyncError)
    }

    func testCreateReminderReturnsWarningWhenTagSyncFails() async throws {
        let persistence = FlakyPersistence()
        let tagStore = TagStore(persistence: persistence)
        let tagManager = TagManager(tagStore: tagStore)
        let eventKitService = TestEventKitService()
        let manager = EventKitManager(eventKitService: eventKitService, tagManager: tagManager)
        let lineId = UUID()

        try await tagManager.addTag(to: lineId, tagName: "family")
        await waitUntil {
            tagStore.getTags(for: lineId).count == 1
        }

        persistence.shouldFail = true

        let result = try await manager.createReminder(
            from: makeReminderParsedResult(),
            originalText: "Call mom tomorrow",
            lineId: lineId
        )

        XCTAssertEqual(eventKitService.createReminderCallCount, 1)
        XCTAssertNotNil(result.tagSyncError)
        XCTAssertEqual(tagStore.getTags(for: lineId).map(\.name), ["family"])
    }
}
