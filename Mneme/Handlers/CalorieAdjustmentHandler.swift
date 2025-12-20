import Foundation

/// Handler for calorie adjustment intents
/// Handles positive and negative calorie adjustments (e.g., "+100 kcal" or "-50 kcal")
final class CalorieAdjustmentHandler: IntentHandler {
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
        
        // 2. Add calorie adjustment
        if let mealKcal = result.mealKcal {
            let sign = mealKcal.value >= 0 ? "+" : ""
            items.append(ParsingResultItem(
                field: "Calories",
                value: String(format: "%@%.0f kcal", sign, mealKcal.value),
                isValid: true,
                errorMessage: nil,
                confidence: mealKcal.confidence
            ))
        }
        
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
