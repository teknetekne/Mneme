import Foundation
import FoundationModels

/// Service for translating text to English using LLM (supports all languages)
nonisolated final class TranslationService {
    nonisolated(unsafe) static let shared = TranslationService()
    
    private nonisolated let model: SystemLanguageModel
    private nonisolated let instructions: Instructions
    
    nonisolated init() {
        self.model = SystemLanguageModel.default
        self.instructions = Instructions(
            """
            You are a translation assistant. Translate the input text to English.
            
            RULES:
            - Translate naturally and preserve meaning
            - Keep proper nouns, names, and brand names as-is
            - For location names, keep original (e.g., "Öncü Döner" stays "Öncü Döner")
            - Preserve time expressions format (e.g., "7'de" -> "at 7")
            - If already English, return as-is
            - Output ONLY the translated text, no explanations
            """
        )
    }
    
    /// Translates text to English using LLM. Returns original text if translation fails.
    nonisolated func translateToEnglish(_ text: String) async -> String {
        // Quick check: if text looks English, skip translation
        if isLikelyEnglish(text) {
            return text
        }
        
        guard model.availability == .available else {
            return text
        }
        
        do {
            let session = LanguageModelSession(instructions: instructions)
            let prompt = Prompt(text)
            
            let response = try await session.respond(options: GenerationOptions(), prompt: { prompt })
            let translated = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            
            return translated.isEmpty ? text : translated
        } catch {
            return text
        }
    }
    
    /// Simple heuristic to detect if text is likely English
    private nonisolated func isLikelyEnglish(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        
        // Common English words in event/reminder context
        let englishIndicators = [
            "today", "tomorrow", "monday", "tuesday", "wednesday", "thursday", "friday",
            "saturday", "sunday", "meeting", "dinner", "lunch", "call", "remind", "at", "pm", "am"
        ]
        
        for indicator in englishIndicators {
            if lowercased.contains(indicator) {
                return true
            }
        }
        
        return false
    }
}

