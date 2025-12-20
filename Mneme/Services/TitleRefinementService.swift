import Foundation
import FoundationModels

@Generable(description: "Refined title response")
private struct TitleRefinementResponse {
    @Guide(description: """
        Extract CORE ACTION/SUBJECT from user text, removing all auxiliary verbs and temporal expressions.
        
        REMOVE these verb types:
        - Reminder verbs: remind, remember, hatırlat, rappeler, recordar, erinnern
        - Scheduling verbs: schedule, book, reserve, planla, réserver, reservar, buchen
        - Action verbs: need to, have to, should, must, gonna, going to, will
        - Auxiliary verbs: do, does, did, am, is, are, was, were
        
        REMOVE temporal expressions:
        - Time: at noon, at 3pm, tomorrow, today, next week, öğlen, yarın, bugün, demain
        - Relative: later, soon, after, before, in 5 minutes, 5 minutes later, sonra, önce, plus tard
        - Absolute: Monday, January, 2025, Pazartesi, Ocak
        
        KEEP:
        - Core action: take medicine, call mom, dinner, meeting
        - Named entities: John, Starbucks, Paris (preserve case and diacritics)
        - Essential context: with John, for project, about budget
        
        FORMAT: lowercase_with_underscores
        
        Examples:
        'remind me to take medicine at noon' -> 'take_medicine'
        'öğlen ilaç içmemi hatırlat' -> 'ilac_ic'
        'schedule dinner with John tomorrow' -> 'dinner_with_john'
        'yarın John ile toplantı planla' -> 'john_ile_toplanti'
        'call mom' -> 'call_mom'
        'annemi ara' -> 'annemi_ara'
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
