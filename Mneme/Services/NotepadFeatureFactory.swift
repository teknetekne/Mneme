import Foundation
import EventKit

enum AppLaunchConfiguration {
    private static let environment = ProcessInfo.processInfo.environment
    private static let arguments = ProcessInfo.processInfo.arguments

    static let isUITesting = arguments.contains("MNEME_UI_TEST_MODE") || environment["MNEME_UI_TEST_MODE"] == "1"
    static let skipOnboarding = isUITesting || environment["MNEME_SKIP_ONBOARDING"] == "1"
    static let forceNLPUnsupported = environment["MNEME_FORCE_NLP_UNAVAILABLE"] == "1"
    static let useStubNLP = environment["MNEME_USE_STUB_NLP"] == "1"
    static let useInMemoryStores = environment["MNEME_USE_IN_MEMORY_STORES"] == "1"
    static let useMockEventKit = environment["MNEME_USE_MOCK_EVENTKIT"] == "1"
}

@MainActor
enum NotepadFeatureFactory {
    static func makeViewModel() -> NotepadViewModel {
        let availabilityProvider: LanguageModelAvailabilityProviding = AppLaunchConfiguration.forceNLPUnsupported
            ? FixedLanguageModelAvailabilityProvider(isAvailable: false)
            : SystemLanguageModelAvailabilityProvider()

        let nlpService: NLPServicing = AppLaunchConfiguration.useStubNLP ? StubNLPService() : NLPService.shared

        if AppLaunchConfiguration.useInMemoryStores {
            let persistence = InMemoryPersistence()
            let tagStore = TagStore(persistence: persistence)
            let tagManager = TagManager(tagStore: tagStore)
            let workSessionStore = WorkSessionStore(persistence: persistence)
            let workSessionManager = WorkSessionManager(workSessionStore: workSessionStore)
            let notepadEntryStore = NotepadEntryStore(persistence: persistence, runMigration: false)
            let eventKitService: EventKitServicing = AppLaunchConfiguration.useMockEventKit ? MockEventKitService() : EventKitService.shared
            let eventKitManager = EventKitManager(eventKitService: eventKitService, tagManager: tagManager)

            return NotepadViewModel(
                tagManager: tagManager,
                eventKitManager: eventKitManager,
                workSessionManager: workSessionManager,
                notepadEntryStore: notepadEntryStore,
                nlpService: nlpService,
                availabilityProvider: availabilityProvider
            )
        }

        let tagManager = TagManager()
        let workSessionManager = WorkSessionManager()
        let eventKitService: EventKitServicing = AppLaunchConfiguration.useMockEventKit ? MockEventKitService() : EventKitService.shared
        let eventKitManager = EventKitManager(eventKitService: eventKitService, tagManager: tagManager)

        return NotepadViewModel(
            tagManager: tagManager,
            eventKitManager: eventKitManager,
            workSessionManager: workSessionManager,
            nlpService: nlpService,
            availabilityProvider: availabilityProvider
        )
    }
}

struct StubNLPService: NLPServicing {
    func parse(text: String) async -> ParsedResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        if let moodEmoji = ["😢", "😕", "😐", "🙂", "😊"].first(where: { trimmed.hasPrefix($0) }) {
            let journalText = String(trimmed.dropFirst(moodEmoji.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return ParsedResult(
                intent: SlotPrediction(value: "journal", confidence: 1.0, source: .foundationModel),
                object: journalText.isEmpty ? nil : SlotPrediction(value: journalText, confidence: 1.0, source: .foundationModel),
                moodEmoji: SlotPrediction(value: moodEmoji, confidence: 1.0, source: .pattern)
            )
        }

        if lowercased.contains("meeting") || lowercased.hasPrefix("event ") {
            return ParsedResult(
                intent: SlotPrediction(value: "event", confidence: 1.0, source: .foundationModel),
                object: SlotPrediction(value: trimmed, confidence: 1.0, source: .foundationModel),
                eventTime: SlotPrediction(value: "15:00", confidence: 1.0, source: .manual),
                eventDay: SlotPrediction(value: "tomorrow", confidence: 1.0, source: .manual)
            )
        }

        if lowercased.contains("remind") || lowercased.contains("call ") {
            return ParsedResult(
                intent: SlotPrediction(value: "reminder", confidence: 1.0, source: .foundationModel),
                object: SlotPrediction(value: trimmed, confidence: 1.0, source: .foundationModel),
                reminderTime: SlotPrediction(value: "09:00", confidence: 1.0, source: .manual),
                reminderDay: SlotPrediction(value: "tomorrow", confidence: 1.0, source: .manual)
            )
        }

        if lowercased.contains("work started") {
            return ParsedResult(
                intent: SlotPrediction(value: "work_start", confidence: 1.0, source: .foundationModel),
                object: SlotPrediction(value: trimmed, confidence: 1.0, source: .foundationModel)
            )
        }

        if lowercased.contains("work ended") {
            return ParsedResult(
                intent: SlotPrediction(value: "work_end", confidence: 1.0, source: .foundationModel),
                object: SlotPrediction(value: trimmed, confidence: 1.0, source: .foundationModel)
            )
        }

        return ParsedResult()
    }
}

final class MockEventKitService: EventKitServicing {
    private let eventStore = EKEventStore()

    func createEventRecord(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String?,
        location: String? = nil,
        url: URL? = nil,
        calendar: EKCalendar? = nil
    ) async throws -> CreatedCalendarItem<EKEvent> {
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes
        event.location = location
        event.url = url
        return CreatedCalendarItem(item: event, identifier: UUID().uuidString)
    }

    func createReminderRecord(
        title: String,
        dueDate: Date?,
        notes: String? = nil,
        locationName: String? = nil,
        url: URL? = nil,
        priority: Int = 0,
        calendar: EKCalendar? = nil
    ) async throws -> CreatedCalendarItem<EKReminder> {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        reminder.url = url
        reminder.priority = priority
        return CreatedCalendarItem(item: reminder, identifier: UUID().uuidString)
    }
}
