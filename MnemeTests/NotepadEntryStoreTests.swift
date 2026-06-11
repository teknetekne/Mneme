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

    func testUpdateEntryReplacesExistingValues() async throws {
        let store = NotepadEntryStore(persistence: InMemoryPersistence(), runMigration: false)
        let id = UUID()
        let original = ParsedNotepadEntry(
            id: id,
            date: Date(),
            originalText: "Coffee",
            intent: "expense",
            object: "Coffee",
            amount: 4
        )
        let updated = ParsedNotepadEntry(
            id: id,
            date: original.date,
            originalText: "Lunch",
            intent: "meal",
            object: "Soup",
            mealKcal: 250
        )

        try await store.addEntry(original)
        await waitUntil { store.entries.count == 1 }

        try await store.updateEntry(updated)
        await waitUntil { store.entries.first?.originalText == "Lunch" }

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.intent, "meal")
        XCTAssertEqual(store.entries.first?.mealKcal, 250)
    }

    func testUpdateEntryFailurePreservesOriginalEntry() async throws {
        let persistence = FlakyPersistence()
        let store = NotepadEntryStore(persistence: persistence, runMigration: false)
        let original = ParsedNotepadEntry(
            date: Date(),
            originalText: "Coffee",
            intent: "expense",
            object: "Coffee"
        )

        try await store.addEntry(original)
        await waitUntil { store.entries.count == 1 }
        persistence.shouldFail = true

        let updated = ParsedNotepadEntry(
            id: original.id,
            date: original.date,
            originalText: "Lunch",
            intent: "meal",
            object: "Soup"
        )

        do {
            try await store.updateEntry(updated)
            XCTFail("Expected updateEntry to throw.")
        } catch {
            XCTAssertEqual(store.entries.count, 1)
            XCTAssertEqual(store.entries.first?.originalText, "Coffee")
            XCTAssertEqual(store.entries.first?.intent, "expense")
        }
    }
}
