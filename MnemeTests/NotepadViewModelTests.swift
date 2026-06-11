import XCTest
@testable import Mneme

@MainActor
final class NotepadViewModelTests: XCTestCase {
    func testProcessLinesPersistsOnlyAfterEventCreationAndStorageSucceed() async throws {
        let persistence = InMemoryPersistence()
        let notepadEntryStore = NotepadEntryStore(persistence: persistence, runMigration: false)
        let tagStore = TagStore(persistence: persistence)
        let tagManager = TagManager(tagStore: tagStore)
        let eventKitService = TestEventKitService()
        let eventKitManager = EventKitManager(eventKitService: eventKitService, tagManager: tagManager)
        let line = LineViewModel(text: "Team sync tomorrow at 3")
        let lineStore = LineStore(initialLines: [line])

        let viewModel = NotepadViewModel(
            lineStore: lineStore,
            tagManager: tagManager,
            eventKitManager: eventKitManager,
            workSessionManager: WorkSessionManager(workSessionStore: WorkSessionStore(persistence: persistence)),
            notepadEntryStore: notepadEntryStore,
            nlpService: StaticNLPService(result: makeEventParsedResult()),
            availabilityProvider: FixedLanguageModelAvailabilityProvider(isAvailable: true)
        )

        viewModel.lineParsingResults[line.id] = makeEventParsingItems()
        lineStore.updateStatus(for: line.id, status: .success)

        await viewModel.processLines()
        await waitUntil { notepadEntryStore.entries.count == 1 }

        XCTAssertEqual(eventKitService.createEventCallCount, 1)
        XCTAssertEqual(notepadEntryStore.entries.first?.originalText, "Team sync tomorrow at 3")
        XCTAssertTrue(viewModel.lineParsingResults.isEmpty)
        XCTAssertEqual(viewModel.snackbarType, .success)
        XCTAssertEqual(viewModel.lines.first?.text, "")
    }

    func testProcessLinesKeepsLineWhenPersistenceFailsAfterEventCreation() async throws {
        let failingPersistence = FlakyPersistence()
        failingPersistence.shouldFail = true
        let notepadEntryStore = NotepadEntryStore(persistence: failingPersistence, runMigration: false)

        let tagPersistence = InMemoryPersistence()
        let tagStore = TagStore(persistence: tagPersistence)
        let tagManager = TagManager(tagStore: tagStore)
        let eventKitService = TestEventKitService()
        let eventKitManager = EventKitManager(eventKitService: eventKitService, tagManager: tagManager)
        let line = LineViewModel(text: "Team sync tomorrow at 3")
        let lineStore = LineStore(initialLines: [line])

        let viewModel = NotepadViewModel(
            lineStore: lineStore,
            tagManager: tagManager,
            eventKitManager: eventKitManager,
            workSessionManager: WorkSessionManager(workSessionStore: WorkSessionStore(persistence: tagPersistence)),
            notepadEntryStore: notepadEntryStore,
            nlpService: StaticNLPService(result: makeEventParsedResult()),
            availabilityProvider: FixedLanguageModelAvailabilityProvider(isAvailable: true)
        )

        viewModel.lineParsingResults[line.id] = makeEventParsingItems()
        lineStore.updateStatus(for: line.id, status: .success)

        await viewModel.processLines()

        XCTAssertEqual(eventKitService.createEventCallCount, 1)
        XCTAssertEqual(viewModel.lineParsingResults[line.id]?.first?.value, "event")
        XCTAssertEqual(lineStore.linesById[line.id]?.text, "Team sync tomorrow at 3")
        XCTAssertEqual(lineStore.linesById[line.id]?.status, .error)
        XCTAssertEqual(viewModel.snackbarType, .error)
    }
}
