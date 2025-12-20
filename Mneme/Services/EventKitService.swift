import Foundation
import EventKit
import Combine

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
        url: URL? = nil
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
        event.calendar = eventStore.defaultCalendarForNewEvents
        
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
        url: URL? = nil
    ) async throws -> EKReminder {
        guard isAuthorized else {
            throw EventKitError.notAuthorized
        }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        reminder.url = url
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        
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

enum EventKitError: LocalizedError {
    case notAuthorized
    
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "EventKit access not authorized"
        }
    }
}
