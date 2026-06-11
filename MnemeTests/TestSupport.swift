import XCTest
import CoreData
import EventKit
@testable import Mneme

final class FlakyPersistence: Persistence {
    let backing = InMemoryPersistence()
    var shouldFail = false
    var injectedError = NSError(domain: "MnemeTests.Persistence", code: 1, userInfo: [NSLocalizedDescriptionKey: "Injected persistence failure"])

    var viewContext: NSManagedObjectContext { backing.viewContext }

    func newBackgroundContext() -> NSManagedObjectContext {
        backing.newBackgroundContext()
    }

    func save() throws {
        if shouldFail { throw injectedError }
        try backing.save()
    }

    func save(context: NSManagedObjectContext) throws {
        if shouldFail { throw injectedError }
        try backing.save(context: context)
    }

    @discardableResult
    func performBackgroundTask<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        if shouldFail { throw injectedError }
        return try await backing.performBackgroundTask(block)
    }
}

final class TestEventKitService: EventKitServicing {
    private let eventStore = EKEventStore()
    private(set) var createEventCallCount = 0
    private(set) var createReminderCallCount = 0
    var nextEventIdentifier = "event-test-id"
    var nextReminderIdentifier = "reminder-test-id"
    var createEventError: Error?
    var createReminderError: Error?

    func createEventRecord(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String?,
        location: String?,
        url: URL?,
        calendar: EKCalendar?
    ) async throws -> CreatedCalendarItem<EKEvent> {
        createEventCallCount += 1
        if let createEventError {
            throw createEventError
        }
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes
        event.location = location
        event.url = url
        return CreatedCalendarItem(item: event, identifier: nextEventIdentifier)
    }

    func createReminderRecord(
        title: String,
        dueDate: Date?,
        notes: String?,
        locationName: String?,
        url: URL?,
        priority: Int,
        calendar: EKCalendar?
    ) async throws -> CreatedCalendarItem<EKReminder> {
        createReminderCallCount += 1
        if let createReminderError {
            throw createReminderError
        }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        reminder.url = url
        reminder.priority = priority
        return CreatedCalendarItem(item: reminder, identifier: nextReminderIdentifier)
    }
}

struct StaticNLPService: NLPServicing {
    let result: ParsedResult

    func parse(text: String) async -> ParsedResult {
        result
    }
}

extension XCTestCase {
    func waitUntil(
        timeout: TimeInterval = 1.0,
        pollIntervalNanoseconds: UInt64 = 20_000_000,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if await MainActor.run(body: condition) {
                return
            }
            try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        }

        XCTFail("Condition was not satisfied within \(timeout) seconds.", file: file, line: line)
    }
}

func makeEventParsingItems(
    subject: String = "Team sync",
    day: String = "tomorrow",
    time: String = "15:00"
) -> [ParsingResultItem] {
    [
        ParsingResultItem(field: "Intent", value: "event", isValid: true, confidence: 1.0),
        ParsingResultItem(field: "Subject", value: subject, isValid: true, confidence: 1.0),
        ParsingResultItem(field: "Event Day", value: day, isValid: true, confidence: 1.0),
        ParsingResultItem(field: "Event Time", value: time, isValid: true, confidence: 1.0)
    ]
}

func makeReminderParsingItems(
    subject: String = "Call mom",
    day: String = "tomorrow",
    time: String = "09:00"
) -> [ParsingResultItem] {
    [
        ParsingResultItem(field: "Intent", value: "reminder", isValid: true, confidence: 1.0),
        ParsingResultItem(field: "Subject", value: subject, isValid: true, confidence: 1.0),
        ParsingResultItem(field: "Reminder Day", value: day, isValid: true, confidence: 1.0),
        ParsingResultItem(field: "Reminder Time", value: time, isValid: true, confidence: 1.0)
    ]
}

func makeEventParsedResult(
    subject: String = "Team sync",
    day: String = "tomorrow",
    time: String = "15:00"
) -> ParsedResult {
    ParsedResult(
        intent: SlotPrediction(value: "event", confidence: 1.0, source: .foundationModel),
        object: SlotPrediction(value: subject, confidence: 1.0, source: .foundationModel),
        eventTime: SlotPrediction(value: time, confidence: 1.0, source: .foundationModel),
        eventDay: SlotPrediction(value: day, confidence: 1.0, source: .foundationModel)
    )
}

func makeReminderParsedResult(
    subject: String = "Call mom",
    day: String = "tomorrow",
    time: String = "09:00"
) -> ParsedResult {
    ParsedResult(
        intent: SlotPrediction(value: "reminder", confidence: 1.0, source: .foundationModel),
        object: SlotPrediction(value: subject, confidence: 1.0, source: .foundationModel),
        reminderTime: SlotPrediction(value: time, confidence: 1.0, source: .foundationModel),
        reminderDay: SlotPrediction(value: day, confidence: 1.0, source: .foundationModel)
    )
}
