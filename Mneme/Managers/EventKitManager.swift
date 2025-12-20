import Foundation
import EventKit
import Combine

// MARK: - EventKit Manager

/// Manages EventKit operations (create reminders/events)
/// Responsibility: Calendar and Reminder creation from parsed results
@MainActor
final class EventKitManager: ObservableObject {
    
    // MARK: - Dependencies
    
    private let eventKitService: EventKitService
    private let tagManager: TagManager
    
    // MARK: - Initialization
    
    init(
        eventKitService: EventKitService? = nil,
        tagManager: TagManager
    ) {
        self.eventKitService = eventKitService ?? .shared
        self.tagManager = tagManager
    }
    
    // MARK: - Reminder Operations
    
    /// Create a reminder from parsed result
    /// - Parameters:
    ///   - result: Parsed NLP result
    ///   - originalText: Original text input
    ///   - lineId: UUID of the line
    ///   - location: Optional location name
    ///   - url: Optional URL
    /// - Returns: Created EKReminder
    @discardableResult
    func createReminder(
        from result: ParsedResult,
        originalText: String,
        lineId: UUID,
        location: String? = nil,
        url: URL? = nil
    ) async throws -> EKReminder {
        // Extract details - use reminderDay and reminderTime for reminders
        let title = result.object?.value ?? originalText
        let day = result.reminderDay?.value
        let time = result.reminderTime?.value
        
        // Format title
        let formattedTitle = formatTitle(title)
        
        // Create reminder via EventKitService
        let reminder = try await eventKitService.createReminder(
            title: formattedTitle,
            dueDate: parseDate(day: day, time: time),
            notes: nil,
            locationName: location,
            url: url
        )
        
        return reminder
    }
    
    // MARK: - Event Operations
    
    /// Create an event from parsed result
    /// - Parameters:
    ///   - result: Parsed NLP result
    ///   - originalText: Original text input
    ///   - lineId: UUID of the line
    ///   - location: Optional location name
    ///   - url: Optional URL
    /// - Returns: Created EKEvent
    @discardableResult
    func createEvent(
        from result: ParsedResult,
        originalText: String,
        lineId: UUID,
        location: String? = nil,
        url: URL? = nil
    ) async throws -> EKEvent {
        // Extract details - use eventDay and eventTime for events
        let title = result.object?.value ?? originalText
        let day = result.eventDay?.value
        let time = result.eventTime?.value ?? (day != nil ? "12:00" : nil) // Default to noon if day exists but time missing
        
        // Format title
        let formattedTitle = formatTitle(title)
        
        // Parse date/time
        let startDate = parseDate(day: day, time: time) ?? Date()
        let endDate = startDate.addingTimeInterval(3600) // 1 hour duration by default
        
        // Create event via EventKitService
        let event = try await eventKitService.createEvent(
            title: formattedTitle,
            startDate: startDate,
            endDate: endDate,
            notes: nil,
            location: location,
            url: url
        )
        
        return event
    }
    
    // MARK: - Private Helpers
    
    /// Format title: capitalize first letter, replace underscores with spaces
    private func formatTitle(_ title: String) -> String {
        let cleaned = title.replacingOccurrences(of: "_", with: " ")
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }
    
    /// Parse day and time strings into Date
    /// - Parameters:
    ///   - day: Day string (e.g., "monday", "tomorrow", "next_friday")
    ///   - time: Time string (e.g., "14:30", "09:00")
    /// - Returns: Parsed Date or nil
    private func parseDate(day: String?, time: String?) -> Date? {
        // Use DateHelper.parseDate which handles both day and time
        return DateHelper.parseDate(dayLabel: day, timeString: time)
    }
}
