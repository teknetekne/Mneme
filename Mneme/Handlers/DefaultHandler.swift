import Foundation

/// Default handler for unknown or unprocessed intents
final class DefaultHandler: IntentHandler {
    func handle(
        result: ParsedResult,
        text: String,
        lineId: UUID
    ) async -> [ParsingResultItem] {
        var items: [ParsingResultItem] = []
        
        // Add intent if available
        if let intent = result.intent {
            items.append(ParsingResultItem(
                field: "Intent",
                value: NotepadFormatter.formatIntentForDisplay(intent.value),
                isValid: true,
                errorMessage: nil,
                confidence: intent.confidence
            ))
        }
        
        // Add object if available
        if let object = result.object {
            items.append(ParsingResultItem(
                field: "Subject",
                value: object.value.capitalized,
                isValid: true,
                errorMessage: nil,
                confidence: object.confidence
            ))
        }
        
        return items
    }
}
