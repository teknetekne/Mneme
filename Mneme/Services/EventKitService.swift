import Foundation
import EventKit
import Combine

struct CreatedCalendarItem<Item> {
    let item: Item
    let identifier: String
}

protocol EventKitServicing {
    func createEventRecord(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String?,
        location: String?,
        url: URL?,
        calendar: EKCalendar?
    ) async throws -> CreatedCalendarItem<EKEvent>

    func createReminderRecord(
        title: String,
        dueDate: Date?,
        notes: String?,
        locationName: String?,
        url: URL?,
        priority: Int,
        calendar: EKCalendar?
    ) async throws -> CreatedCalendarItem<EKReminder>
}

final class EventKitService: ObservableObject {
    static let shared = EventKitService()
    
    private let eventStore = EKEventStore()
    
    @Published private(set) var authorizationStatus: EKAuthorizationStatus = .notDetermined
    
    private init() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }
    
    // MARK: - Authorization
    
    var isAuthorized: Bool {
        if #available(iOS 17.0, macOS 14.0, *) {
            let eventStatus = EKEventStore.authorizationStatus(for: .event)
            let reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
            return eventStatus == .fullAccess && reminderStatus == .fullAccess
        } else {
            let eventStatus = EKEventStore.authorizationStatus(for: .event)
            let reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
            return eventStatus == .authorized && reminderStatus == .authorized
        }
    }
    
    func requestFullAccess() async -> Bool {
        if #available(iOS 17.0, macOS 14.0, *) {
            do {
                let eventGranted = try await eventStore.requestFullAccessToEvents()
                let reminderGranted = try await eventStore.requestFullAccessToReminders()
                
                await MainActor.run {
                    authorizationStatus = EKEventStore.authorizationStatus(for: .event)
                }
                
                return eventGranted && reminderGranted
            } catch {
                return false
            }
        } else {
            do {
                let eventStatus = try await eventStore.requestAccess(to: .event)
                let reminderStatus = try await eventStore.requestAccess(to: .reminder)
                
                await MainActor.run {
                    authorizationStatus = EKEventStore.authorizationStatus(for: .event)
                }
                
                return eventStatus && reminderStatus
            } catch {
                return false
            }
        }
    }
    
    // MARK: - Calendars
    
    func getCalendars(for entityType: EKEntityType) -> [EKCalendar] {
        guard isAuthorized else { return [] }
        return eventStore.calendars(for: entityType)
    }
    
    // MARK: - Events
    
    func getEvents(startDate: Date, endDate: Date) -> [EKEvent] {
        guard isAuthorized else { return [] }
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        return eventStore.events(matching: predicate)
    }
    
    func getEvent(byIdentifier identifier: String) -> EKEvent? {
        guard isAuthorized else { return nil }
        return eventStore.event(withIdentifier: identifier)
    }
    
    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String?,
        location: String? = nil,
        url: URL? = nil,
        calendar: EKCalendar? = nil
    ) async throws -> EKEvent {
        guard isAuthorized else {
            throw EventKitError.notAuthorized
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes
        event.location = location
        event.url = url
        event.calendar = calendar ?? eventStore.defaultCalendarForNewEvents
        
        try eventStore.save(event, span: .thisEvent, commit: true)
        return event
    }
    
    // ... updateEvent ... (skipping updateEvent for now as it wasn't requested, but good to keep in mind)

    func updateEvent(_ event: EKEvent, title: String, startDate: Date, endDate: Date, notes: String?, location: String? = nil, url: URL? = nil) throws {
        guard isAuthorized else {
            throw EventKitError.notAuthorized
        }
        
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes
        event.location = location
        event.url = url
        
        try eventStore.save(event, span: .thisEvent, commit: true)
    }
    
    func deleteEvent(_ event: EKEvent) throws {
        guard isAuthorized else {
            throw EventKitError.notAuthorized
        }
        
        try eventStore.remove(event, span: .thisEvent, commit: true)
    }
    
    // MARK: - Reminders
    
    func getReminder(byIdentifier identifier: String) -> EKReminder? {
        guard isAuthorized else { return nil }
        return eventStore.calendarItem(withIdentifier: identifier) as? EKReminder
    }
    
    func getReminders(includeCompleted: Bool) async -> [EKReminder] {
        guard isAuthorized else { return [] }
        
        return await withCheckedContinuation { continuation in
            let predicate = eventStore.predicateForReminders(in: nil)
            
            eventStore.fetchReminders(matching: predicate) { reminders in
                guard let reminders = reminders else {
                    continuation.resume(returning: [])
                    return
                }
                
                if includeCompleted {
                    continuation.resume(returning: reminders)
                } else {
                    continuation.resume(returning: reminders.filter { !$0.isCompleted })
                }
            }
        }
    }
    
    func createReminder(
        title: String,
        dueDate: Date?,
        notes: String? = nil,
        locationName: String? = nil,
        url: URL? = nil,
        priority: Int = 0,
        calendar: EKCalendar? = nil
    ) async throws -> EKReminder {
        guard isAuthorized else {
            throw EventKitError.notAuthorized
        }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        reminder.url = url
        reminder.priority = priority
        reminder.calendar = calendar ?? eventStore.defaultCalendarForNewReminders()
        
        if let dueDate = dueDate {
            let alarm = EKAlarm(absoluteDate: dueDate)
            reminder.addAlarm(alarm)
            
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            reminder.dueDateComponents = components
        }
        
        if let locationName = locationName, !locationName.isEmpty {
            let location = EKStructuredLocation(title: locationName)
            let locationAlarm = EKAlarm()
            locationAlarm.structuredLocation = location
            locationAlarm.proximity = .enter
            reminder.addAlarm(locationAlarm)
        }
        
        try eventStore.save(reminder, commit: true)
        return reminder
    }
    
    func saveReminder(_ reminder: EKReminder) throws {
        guard isAuthorized else {
            throw EventKitError.notAuthorized
        }
        
        try eventStore.save(reminder, commit: true)
    }
    
    func completeReminder(_ reminder: EKReminder) throws {
        guard isAuthorized else {
            throw EventKitError.notAuthorized
        }
        
        reminder.isCompleted = true
        try eventStore.save(reminder, commit: true)
    }
    
    func deleteReminder(_ reminder: EKReminder) throws {
        guard isAuthorized else {
            throw EventKitError.notAuthorized
        }
        
        try eventStore.remove(reminder, commit: true)
    }
}

extension EventKitService: EventKitServicing {
    func createEventRecord(
        title: String,
        startDate: Date,
        endDate: Date,
        notes: String?,
        location: String? = nil,
        url: URL? = nil,
        calendar: EKCalendar? = nil
    ) async throws -> CreatedCalendarItem<EKEvent> {
        let event = try await createEvent(
            title: title,
            startDate: startDate,
            endDate: endDate,
            notes: notes,
            location: location,
            url: url,
            calendar: calendar
        )

        let identifier = event.calendarItemIdentifier
        guard !identifier.isEmpty else {
            throw EventKitError.missingIdentifier
        }

        return CreatedCalendarItem(item: event, identifier: identifier)
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
        let reminder = try await createReminder(
            title: title,
            dueDate: dueDate,
            notes: notes,
            locationName: locationName,
            url: url,
            priority: priority,
            calendar: calendar
        )

        let identifier = reminder.calendarItemIdentifier
        guard !identifier.isEmpty else {
            throw EventKitError.missingIdentifier
        }

        return CreatedCalendarItem(item: reminder, identifier: identifier)
    }
}

enum EventKitError: LocalizedError {
    case notAuthorized
    case missingIdentifier
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "EventKit access not authorized"
        case .missingIdentifier:
            return "Calendar item identifier was unavailable after save"
        }
    }
}
