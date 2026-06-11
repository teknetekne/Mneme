import Foundation
import EventKit
import Combine

// MARK: - EventKit Manager

/// Manages EventKit operations (create reminders/events)
/// Responsibility: Calendar and Reminder creation from parsed results
@MainActor
final class EventKitManager: ObservableObject {
    struct CalendarItemCreationResult<Item> {
        let item: Item
        let identifier: String
        let tagSyncError: Error?
    }
    
    // MARK: - Dependencies
    
    private let eventKitService: EventKitServicing
    private let tagManager: TagManager
    
    // MARK: - Initialization
    
    init(
        eventKitService: EventKitServicing,
        tagManager: TagManager
    ) {
        self.eventKitService = eventKitService
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
    /// - Returns: Created reminder and tag sync status
    @discardableResult
    func createReminder(
        from result: ParsedResult,
        originalText: String,
        lineId: UUID,
        location: String? = nil,
        url: URL? = nil
    ) async throws -> CalendarItemCreationResult<EKReminder> {
        // Extract details - use reminderDay and reminderTime for reminders
        let title = result.object?.value ?? originalText
        let day = result.reminderDay?.value
        let time = result.reminderTime?.value
        
        // Format title
        let formattedTitle = formatTitle(title)
        
        // Create reminder via EventKitService
        let reminder = try await eventKitService.createReminderRecord(
            title: formattedTitle,
            dueDate: parseDate(day: day, time: time),
            notes: nil,
            locationName: location,
            url: url,
            priority: 0,
            calendar: nil
        )

        let tagSyncError: Error?
        do {
            try await tagManager.commitTags(from: lineId, toReminderIdentifier: reminder.identifier)
            tagSyncError = nil
        } catch {
            tagSyncError = error
        }

        return CalendarItemCreationResult(
            item: reminder.item,
            identifier: reminder.identifier,
            tagSyncError: tagSyncError
        )
    }
    
    // MARK: - Event Operations
    
    /// Create an event from parsed result
    /// - Parameters:
    ///   - result: Parsed NLP result
    ///   - originalText: Original text input
    ///   - lineId: UUID of the line
    ///   - location: Optional location name
    ///   - url: Optional URL
    /// - Returns: Created event and tag sync status
    @discardableResult
    func createEvent(
        from result: ParsedResult,
        originalText: String,
        lineId: UUID,
        location: String? = nil,
        url: URL? = nil
    ) async throws -> CalendarItemCreationResult<EKEvent> {
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
        let event = try await eventKitService.createEventRecord(
            title: formattedTitle,
            startDate: startDate,
            endDate: endDate,
            notes: nil,
            location: location,
            url: url,
            calendar: nil
        )

        let tagSyncError: Error?
        do {
            try await tagManager.commitTags(from: lineId, toEventIdentifier: event.identifier)
            tagSyncError = nil
        } catch {
            tagSyncError = error
        }

        return CalendarItemCreationResult(
            item: event.item,
            identifier: event.identifier,
            tagSyncError: tagSyncError
        )
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
