import Foundation

/// Protocol for intent-specific handlers
/// Each handler processes a specific intent type and returns UI-ready results
protocol IntentHandler {
    /// Process parsed result and return UI-ready results
    /// - Parameters:
    ///   - result: Parsed result from NLP service
    ///   - text: Original input text
    ///   - lineId: UUID of the line being processed
    /// - Returns: Array of parsing result items for UI display
    func handle(
        result: ParsedResult,
        text: String,
        lineId: UUID
    ) async -> [ParsingResultItem]
}

/// Factory for creating appropriate handler based on intent
final class HandlerFactory {
    /// Get the appropriate handler for a given intent
    /// - Parameter intent: The intent value (can be display format or raw)
    /// - Returns: An intent handler instance
    static func handler(for intent: String) -> IntentHandler {
        let normalized = NotepadFormatter.normalizeIntentForCheck(intent)
        
        switch normalized {
        case "meal":
            return MealHandler()
        case "event", "reminder":
            return EventHandler()
        case "expense", "income":
            return ExpenseHandler()
        case "activity":
            return ActivityHandler()
        case "work_start", "work_end":
            return WorkSessionHandler()
        case "calorie_adjustment":
            return CalorieAdjustmentHandler()
        case "journal":
            return JournalHandler()
        default:
            return DefaultHandler()
        }
    }
}
