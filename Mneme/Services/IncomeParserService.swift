import Foundation
import FoundationModels

@Generable(description: "Parsed income entry")
struct IncomeParsedEntry {
    @Guide(description: "Income source name (e.g., 'salary' -> 'salary', 'freelance work' -> 'freelance_work'). Use lowercase with underscores.")
    let object: String
    
    @Guide(description: "Currency code (e.g., USD, EUR, TRY) if explicitly mentioned. If not mentioned, leave as nil. NEVER use 'none' or empty string.")
    let currency: String?
    
    @Guide(description: "Amount value as a number if explicitly mentioned. If not mentioned, leave as nil. NEVER use 0.0 as default.")
    let amount: Double?
}

actor IncomeParserService {
    static let shared = IncomeParserService()
    
    private let model: SystemLanguageModel
    private let instructions: Instructions
    
    init() {
        self.model = SystemLanguageModel.default
        self.instructions = Instructions(
            """
            Parse income information from user input in ANY language. Extract object, amount, and currency.
            
            RULES:
            - object: Source of income. Preserve original language.
            - amount: Numeric value.
            - currency: Currency code (USD, EUR, TRY, GBP, etc.). Default to user's locale currency if not specified but implied.
            """
        )
    }
    
    func parse(text: String) async -> (object: String, amount: Double?, currency: String?) {
        guard model.availability == .available else {
            return (object: text, amount: nil, currency: nil)
        }
        
        do {
            let prompt = Prompt(text)
            let session = LanguageModelSession(instructions: instructions)
            
            let response = try await session.respond(generating: IncomeParsedEntry.self, includeSchemaInPrompt: true, options: GenerationOptions(), prompt: { prompt })
            
            return (response.content.object, response.content.amount, response.content.currency)
        } catch {
            return (object: text, amount: nil, currency: nil)
        }
    }
}

