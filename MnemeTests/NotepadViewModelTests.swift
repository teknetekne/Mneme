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

    func testProcessLinesDoesNotCreateEventWhenPersistenceFails() async throws {
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

        XCTAssertEqual(eventKitService.createEventCallCount, 0)
        XCTAssertEqual(viewModel.lineParsingResults[line.id]?.first?.value, "event")
        XCTAssertEqual(lineStore.linesById[line.id]?.text, "Team sync tomorrow at 3")
        XCTAssertEqual(lineStore.linesById[line.id]?.status, .error)
        XCTAssertEqual(viewModel.snackbarType, .error)
    }

    func testProcessLinesRemovesPendingEntryWhenEventCreationFails() async throws {
        let persistence = InMemoryPersistence()
        let notepadEntryStore = NotepadEntryStore(persistence: persistence, runMigration: false)
        let tagStore = TagStore(persistence: persistence)
        let tagManager = TagManager(tagStore: tagStore)
        let eventKitService = TestEventKitService()
        eventKitService.createEventError = NSError(
            domain: "MnemeTests.EventKit",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Injected EventKit failure"]
        )
        let line = LineViewModel(text: "Team sync tomorrow at 3")
        let lineStore = LineStore(initialLines: [line])
        let viewModel = NotepadViewModel(
            lineStore: lineStore,
            tagManager: tagManager,
            eventKitManager: EventKitManager(eventKitService: eventKitService, tagManager: tagManager),
            workSessionManager: WorkSessionManager(workSessionStore: WorkSessionStore(persistence: persistence)),
            notepadEntryStore: notepadEntryStore,
            nlpService: StaticNLPService(result: makeEventParsedResult()),
            availabilityProvider: FixedLanguageModelAvailabilityProvider(isAvailable: true)
        )

        viewModel.lineParsingResults[line.id] = makeEventParsingItems()
        lineStore.updateStatus(for: line.id, status: .success)

        await viewModel.processLines()
        await waitUntil { notepadEntryStore.entries.isEmpty }

        XCTAssertEqual(eventKitService.createEventCallCount, 1)
        XCTAssertTrue(notepadEntryStore.entries.isEmpty)
        XCTAssertEqual(lineStore.linesById[line.id]?.status, .error)
    }

    func testWorkStartWaitsForConfirmationBeforePersistingHistory() async throws {
        let persistence = InMemoryPersistence()
        let workSessionStore = WorkSessionStore(persistence: persistence)
        _ = try await workSessionStore.recordWorkStart(
            date: Date(),
            time: "09:00",
            object: "Existing"
        )
        await waitUntil { workSessionStore.getActiveWorkSession() != nil }

        let notepadEntryStore = NotepadEntryStore(persistence: persistence, runMigration: false)
        let tagManager = TagManager(tagStore: TagStore(persistence: persistence))
        let line = LineViewModel(text: "Work started on Mneme")
        let lineStore = LineStore(initialLines: [line])
        let workResult = ParsedResult(
            intent: SlotPrediction(value: "work_start", confidence: 1, source: .foundationModel),
            object: SlotPrediction(value: "Mneme", confidence: 1, source: .foundationModel)
        )
        let viewModel = NotepadViewModel(
            lineStore: lineStore,
            tagManager: tagManager,
            eventKitManager: EventKitManager(eventKitService: TestEventKitService(), tagManager: tagManager),
            workSessionManager: WorkSessionManager(workSessionStore: workSessionStore),
            notepadEntryStore: notepadEntryStore,
            nlpService: StaticNLPService(result: workResult),
            availabilityProvider: FixedLanguageModelAvailabilityProvider(isAvailable: true)
        )

        viewModel.lineParsingResults[line.id] = [
            ParsingResultItem(field: "Intent", value: "work_start", isValid: true, confidence: 1),
            ParsingResultItem(field: "Subject", value: "Mneme", isValid: true, confidence: 1)
        ]
        lineStore.updateStatus(for: line.id, status: .success)

        await viewModel.processLines()

        XCTAssertTrue(viewModel.showWorkSessionConfirmation)
        XCTAssertTrue(notepadEntryStore.entries.isEmpty)
        XCTAssertEqual(lineStore.linesById[line.id]?.text, "Work started on Mneme")

        viewModel.cancelWorkStartReplacement()

        XCTAssertFalse(viewModel.showWorkSessionConfirmation)
        XCTAssertTrue(notepadEntryStore.entries.isEmpty)
        XCTAssertEqual(workSessionStore.sessions.filter { $0.endTime == nil }.count, 1)
    }

    func testConfirmingWorkStartPersistsHistoryAndReplacesSession() async throws {
        let persistence = InMemoryPersistence()
        let workSessionStore = WorkSessionStore(persistence: persistence)
        _ = try await workSessionStore.recordWorkStart(
            date: Date(),
            time: "09:00",
            object: "Existing"
        )
        await waitUntil { workSessionStore.getActiveWorkSession() != nil }

        let notepadEntryStore = NotepadEntryStore(persistence: persistence, runMigration: false)
        let tagManager = TagManager(tagStore: TagStore(persistence: persistence))
        let line = LineViewModel(text: "Work started on Mneme")
        let lineStore = LineStore(initialLines: [line])
        let workResult = ParsedResult(
            intent: SlotPrediction(value: "work_start", confidence: 1, source: .foundationModel),
            object: SlotPrediction(value: "Mneme", confidence: 1, source: .foundationModel)
        )
        let viewModel = NotepadViewModel(
            lineStore: lineStore,
            tagManager: tagManager,
            eventKitManager: EventKitManager(eventKitService: TestEventKitService(), tagManager: tagManager),
            workSessionManager: WorkSessionManager(workSessionStore: workSessionStore),
            notepadEntryStore: notepadEntryStore,
            nlpService: StaticNLPService(result: workResult),
            availabilityProvider: FixedLanguageModelAvailabilityProvider(isAvailable: true)
        )

        viewModel.lineParsingResults[line.id] = [
            ParsingResultItem(field: "Intent", value: "work_start", isValid: true, confidence: 1),
            ParsingResultItem(field: "Subject", value: "Mneme", isValid: true, confidence: 1)
        ]
        lineStore.updateStatus(for: line.id, status: .success)

        await viewModel.processLines()
        viewModel.confirmWorkStartReplacement()

        await waitUntil {
            notepadEntryStore.entries.count == 1
                && workSessionStore.sessions.count == 2
                && workSessionStore.sessions.filter { $0.endTime == nil }.count == 1
                && lineStore.linesById[line.id] == nil
        }

        XCTAssertEqual(notepadEntryStore.entries.first?.id, line.id)
        XCTAssertEqual(workSessionStore.getActiveWorkSession()?.object, "Mneme")
        XCTAssertFalse(viewModel.showWorkSessionConfirmation)
    }
}
