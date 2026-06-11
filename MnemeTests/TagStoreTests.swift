import XCTest
@testable import Mneme

@MainActor
final class TagStoreTests: XCTestCase {
    func testCommitTagsMovesAssignmentsToEventIdentifier() async throws {
        let store = TagStore(persistence: InMemoryPersistence())
        let lineId = UUID()

        try await store.assignTagByName("work", to: lineId)
        await waitUntil {
            store.getTags(for: lineId).count == 1
        }

        try await store.commitTags(from: lineId, toEventIdentifier: "event-123")

        await waitUntil {
            store.getTags(for: lineId).isEmpty && store.getTags(forEventIdentifier: "event-123").count == 1
        }

        XCTAssertTrue(store.getTags(for: lineId).isEmpty)
        XCTAssertEqual(store.getTags(forEventIdentifier: "event-123").map(\.name), ["work"])
    }

    func testCommitTagsFailureLeavesLineAssignmentsIntact() async throws {
        let persistence = FlakyPersistence()
        let store = TagStore(persistence: persistence)
        let lineId = UUID()

        try await store.assignTagByName("health", to: lineId)
        await waitUntil {
            store.getTags(for: lineId).count == 1
        }

        persistence.shouldFail = true

        do {
            try await store.commitTags(from: lineId, toEventIdentifier: "event-456")
            XCTFail("Expected commitTags to throw.")
        } catch {
            XCTAssertEqual((error as NSError).localizedDescription, persistence.injectedError.localizedDescription)
        }

        XCTAssertEqual(store.getTags(for: lineId).map(\.name), ["health"])
        XCTAssertTrue(store.getTags(forEventIdentifier: "event-456").isEmpty)
    }
}
