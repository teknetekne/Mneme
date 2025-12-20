import Foundation

/// Handler for activity intents (workouts, exercises)
/// Handles duration, distance, and calorie calculation
final class ActivityHandler: IntentHandler {
    private let activityParserService = ActivityParserService.shared
    
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
        
        // 2. Parse activity using ActivityParserService
        if let activityResult = await activityParserService.parseActivity(from: text) {
            // Add activity type
            items.append(ParsingResultItem(
                field: "Activity",
                value: activityResult.activityType.capitalized,
                isValid: true,
                errorMessage: nil,
                confidence: result.intent?.confidence
            ))
            
            // Add duration if available
            if let formattedDuration = activityResult.formattedDuration {
                items.append(ParsingResultItem(
                    field: "Duration",
                    value: formattedDuration,
                    isValid: true,
                    errorMessage: nil,
                    confidence: result.duration?.confidence
                ))
            }
            
            // Add distance if available
            if let formattedDistance = activityResult.formattedDistance {
                items.append(ParsingResultItem(
                    field: "Distance",
                    value: formattedDistance,
                    isValid: true,
                    errorMessage: nil,
                    confidence: result.distance?.confidence
                ))
            }
            
            // Add calories burned or error
            if let errorMessage = activityResult.errorMessage {
                items.append(ParsingResultItem(
                    field: "Calories Burned",
                    value: "Error",
                    isValid: false,
                    errorMessage: errorMessage,
                    confidence: nil
                ))
            } else {
                items.append(ParsingResultItem(
                    field: "Calories Burned",
                    value: activityResult.formattedCalories,
                    isValid: activityResult.caloriesBurned > 0,
                    errorMessage: activityResult.caloriesBurned <= 0 ? "Unable to calculate calories" : nil,
                    confidence: nil
                ))
            }
        }
        
        return items
    }
}
