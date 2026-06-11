import XCTest
@testable import Mneme

@MainActor
final class NotepadEntryStoreTests: XCTestCase {
    func testAddEntryPersistsAndPublishes() async throws {
        let store = NotepadEntryStore(persistence: InMemoryPersistence(), runMigration: false)
        let entry = ParsedNotepadEntry(date: Date(), originalText: "Lunch", intent: "meal", object: "Soup")

        try await store.addEntry(entry)

        await waitUntil {
            store.entries.count == 1
        }

        XCTAssertEqual(store.entries.first?.originalText, "Lunch")
        XCTAssertEqual(store.entries.first?.intent, "meal")
    }

    func testDeleteEntryRemovesPersistedItem() async throws {
        let store = NotepadEntryStore(persistence: InMemoryPersistence(), runMigration: false)
        let entry = ParsedNotepadEntry(date: Date(), originalText: "Coffee", intent: "expense", object: "Coffee")

        try await store.addEntry(entry)
        await waitUntil { store.entries.count == 1 }

        try await store.deleteEntry(entry)
        await waitUntil { store.entries.isEmpty }

        XCTAssertTrue(store.entries.isEmpty)
    }

    func testAddEntryThrowsWhenPersistenceFails() async {
        let persistence = FlakyPersistence()
        persistence.shouldFail = true
        let store = NotepadEntryStore(persistence: persistence, runMigration: false)
        let entry = ParsedNotepadEntry(date: Date(), originalText: "Rent", intent: "expense", object: "Rent")

        do {
            try await store.addEntry(entry)
            XCTFail("Expected addEntry to throw.")
        } catch {
            XCTAssertEqual((error as NSError).localizedDescription, persistence.injectedError.localizedDescription)
        }
    }
}
