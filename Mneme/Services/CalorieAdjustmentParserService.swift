import Foundation
import FoundationModels

@Generable(description: "Parsed calorie adjustment entry")
struct CalorieAdjustmentParsedEntry {
    @Guide(description: "Calorie adjustment amount as a number. Can be positive or negative (e.g., '+100 kcal' -> 100, '-50 calories' -> -50). For multiple adjustments, calculate net value (e.g., '+100 kcal -50 kcal' -> 50).")
    let mealKcal: Double
}

actor CalorieAdjustmentParserService {
    static let shared = CalorieAdjustmentParserService()
    
    private let model: SystemLanguageModel
    private let instructions: Instructions
    
    init() {
        self.model = SystemLanguageModel.default
        self.instructions = Instructions(
            """
            Parse calorie adjustment from user input. Extract the numeric value (positive or negative).
            """
        )
    }
    
    func parse(text: String) async -> Double? {
        guard model.availability == .available else { return nil }
        
        do {
            let prompt = Prompt(text)
            let session = LanguageModelSession(instructions: instructions)
            
            let response = try await session.respond(generating: CalorieAdjustmentParsedEntry.self, includeSchemaInPrompt: true, options: GenerationOptions(), prompt: { prompt })
            
            return response.content.mealKcal
        } catch {
            return nil
        }
    }
}

