import Foundation

/// Handler for work session intents (work_start, work_end)
/// Injects current time for work tracking
final class WorkSessionHandler: IntentHandler {
    func handle(
        result: ParsedResult,
        text: String,
        lineId: UUID
    ) async -> [ParsingResultItem] {
        var items: [ParsingResultItem] = []
        
        // 1. Add intent
        if let intent = result.intent {
            items.append(ParsingResultItem(
                field: "Intent",
                value: NotepadFormatter.formatIntentForDisplay(intent.value),
                isValid: true,
                errorMessage: nil,
                confidence: intent.confidence
            ))
        }
        
        // 2. Add current time as Event Time
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        let currentTime = formatter.string(from: Date())
        
        let isValid = NotepadValidator.isValidTime(currentTime)
        let displayTime = NotepadFormatter.formatTimeForDisplay(currentTime)
        let finalTime = displayTime.isEmpty ? currentTime : displayTime
        
        items.append(ParsingResultItem(
            field: "Event Time",
            value: finalTime,
            isValid: isValid,
            errorMessage: isValid ? nil : "Invalid time format",
            rawValue: currentTime,
            confidence: result.intent?.confidence
        ))
        
        // 3. Add subject if available
        if let object = result.object {
            let displayObject = object.value.replacingOccurrences(of: "_", with: " ").capitalized
            items.append(ParsingResultItem(
                field: "Subject",
                value: displayObject,
                isValid: true,
                errorMessage: nil,
                rawValue: object.value,
                confidence: object.confidence
            ))
        }
        
        return items
    }
}
