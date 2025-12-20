import Foundation
import FoundationModels

@Generable(description: "Parsed work session entry")
struct WorkSessionParsedEntry {
    @Guide(description: "Work description or project name (e.g., 'project X' -> 'project_x', 'coding' -> 'coding'). Use lowercase with underscores.")
    let object: String?
}

actor WorkSessionParserService {
    static let shared = WorkSessionParserService()
    
    private let model: SystemLanguageModel
    private let instructions: Instructions
    
    init() {
        self.model = SystemLanguageModel.default
        self.instructions = Instructions(
            """
            Parse work session information from user input. Extract project or task name if present.
            """
        )
    }
    
    func parse(text: String) async -> String? {
        guard model.availability == .available else { return nil }
        
        do {
            let prompt = Prompt(text)
            let session = LanguageModelSession(instructions: instructions)
            
            let response = try await session.respond(generating: WorkSessionParsedEntry.self, includeSchemaInPrompt: true, options: GenerationOptions(), prompt: { prompt })
            
            return response.content.object
        } catch {
            return nil
        }
    }
}

