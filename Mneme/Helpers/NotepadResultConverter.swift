import Foundation

struct NotepadResultConverter {
    static func convertToParsedResult(from items: [ParsingResultItem], originalText: String) -> ParsedResult {
        var result = ParsedResult()
        
        for item in items {
            guard item.isValid else { continue }
            switch item.field {
            case "Intent":
                let intentValue = NotepadFormatter.normalizeIntentForCheck(item.value)
                result.intent = SlotPrediction(value: intentValue, confidence: nil, source: .pattern)
            case "Subject":
                let raw = item.rawValue ?? item.value
                result.object = SlotPrediction(value: raw, confidence: nil, source: .pattern)
            case "Reminder Time":
                let raw = item.rawValue ?? item.value
                result.reminderTime = SlotPrediction(value: raw, confidence: nil, source: .pattern)
            case "Reminder Day":
                let raw = item.rawValue ?? item.value
                result.reminderDay = SlotPrediction(value: raw, confidence: nil, source: .pattern)
            case "Event Time":
                let raw = item.rawValue ?? item.value
                result.eventTime = SlotPrediction(value: raw, confidence: nil, source: .pattern)
            case "Event Day":
                let raw = item.rawValue ?? item.value
                result.eventDay = SlotPrediction(value: raw, confidence: nil, source: .pattern)
            case "Currency":
                result.currency = SlotPrediction(value: item.value, confidence: nil, source: .pattern)
            case "Amount":
                if let amount = Double(item.value.replacingOccurrences(of: " ", with: "")) {
                    result.amount = SlotPrediction(value: amount, confidence: nil, source: .pattern)
                }
            case "Duration":
                if let minutes = Double(item.value.replacingOccurrences(of: " minutes", with: "").replacingOccurrences(of: " ", with: "")) {
                    result.duration = SlotPrediction(value: minutes, confidence: nil, source: .pattern)
                }
            case "Distance":
                if let km = Double(item.value.replacingOccurrences(of: " km", with: "").replacingOccurrences(of: " ", with: "")) {
                    result.distance = SlotPrediction(value: km, confidence: nil, source: .pattern)
                }
            case "Meal Quantity":
                result.mealQuantity = SlotPrediction(value: item.value, confidence: nil, source: .pattern)
            case "Calories":
                if let kcal = Double(item.value.replacingOccurrences(of: " kcal", with: "").replacingOccurrences(of: " ", with: "")) {
                    result.mealKcal = SlotPrediction(value: kcal, confidence: nil, source: .pattern)
                }
            default:
                break
            }
        }
        
        return result
    }
}
