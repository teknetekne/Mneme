import Foundation
import FoundationModels
@Generable(description: "Refined title response")
private struct TitleRefinementResponse {
    @Guide(description: """
        You are a smart calendar assistant. Your goal is to generate a concise, natural DISPLAY TITLE for an event based on the user's input.
        
        CONTEXT:
        The date and time have already been extracted. Your job is ONLY the title.
        
        GUIDELINES:
        1. Identify the Core Activity: What is actually happening? (Meeting, Dinner, Call, Shopping).
        2. Preserve People/Context: "Meeting" is too vague. "Meeting with Alice" is perfect. Always keep WHO the event is with.
        3. Remove Redundancy verbs: Remove "var", "yap", "planla", "remind", "schedule". (e.g., "Toplantı var" -> "Toplantı").
        4. Remove Temporal Suffixes: usage like "Çarşamba günü" -> remove BOTH "Çarşamba" and "günü".
        5. Preserve Compound Nouns: "Dinner" is generic, but "Gala Dinner" is specific. Keep specific phrases.
        6. Preserve Language: Output within the same language and alphabet as the input.
        
        EXAMPLES:
        Input: "Yarın sabah Ahmet'le toplantı var" -> Output: "Ahmet'le Toplantı"
        Input: "Online toplantım var yarın" -> Output: "Online Toplantı"
        Input: "Kankalarla halı saha çarşamba günü" -> Output: "Kankalarla Halı Saha"
        Input: "Buse ile konser" -> Output: "Buse ile Konser"
        Input: "Schedule a dentist appointment for Friday" -> Output: "Dentist Appointment"
        Input: "Akşam yemeği planla" -> Output: "Akşam Yemeği"
        Input: "Annemi aramayı hatırlat" -> Output: "Annemi Ara"
        Input: "Öğlen ilaç içmemi anımsat" -> Output: "İlaç İç"
        Input: "Meeting with marketing team" -> "Meeting with Marketing Team"
        """)
    let title: String
}
actor TitleRefinementService {
    static let shared = TitleRefinementService()
    private let model: SystemLanguageModel
    private let instructions: Instructions
    init() {
        self.model = SystemLanguageModel.default
        self.instructions = Instructions(
            """
            Refine the title of an event or reminder. Make it concise and natural.
            Remove date/time information if it's already captured in metadata.
            Preserve the original language.
            """
        )
    }
    func refineTitle(originalText: String, fallbackTitle: String, intent: String, dayLabel: String?, timeLabel: String?) async -> String {
        guard model.availability == .available else {
            return sanitize(fallbackTitle, fallback: fallbackTitle)
        }
        let context = """
        intent: \(intent)
        fallback_title: \(fallbackTitle.replacingOccurrences(of: "_", with: " "))
        day: \(dayLabel ?? "unknown")
        time: \(timeLabel ?? "unknown")
        user_text: \(originalText)
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let prompt = Prompt(context)
            let response = try await session.respond(
                generating: TitleRefinementResponse.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(),
                prompt: { prompt }
            )
            let cleaned = sanitize(response.content.title, fallback: fallbackTitle)
            return cleaned
        } catch is LanguageModelSession.GenerationError {
            // Guardrail violations, sensitive content -> return to fallback
            return sanitize(fallbackTitle, fallback: fallbackTitle)
        } catch {
            return sanitize(fallbackTitle, fallback: fallbackTitle)
        }
    }
    
    private func sanitize(_ title: String, fallback: String) -> String {
        let candidate = title
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "__", with: "_")
        
        // Reject too-short or empty outputs; cap length to avoid rambling
        if candidate.isEmpty || candidate.count < 3 {
            return fallback
        }
        if candidate.count > 40 {
            return String(candidate.prefix(40))
        }
        return candidate
    }
}