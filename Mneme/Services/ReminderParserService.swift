import Foundation
import FoundationModels

@Generable(description: "Parsed reminder entry")
struct ReminderParsedEntry {
    @Guide(description: "What to remember (e.g., 'call mom' -> 'call_mom', 'buy groceries' -> 'buy_groceries'). Use lowercase with underscores.")
    let object: String
    
    @Guide(description: "Reminder day: today, tomorrow, monday-sunday, next_monday-next_sunday, or dates like '22 nov'. If 'next week' without specific day, use 'next_monday'. SPECIAL: 'tonight' or 'bu akşam' means today, so use 'today'.")
    let reminderDay: String?
    
    @Guide(description: "Reminder time in 24-hour HH:MM format. ONLY if explicitly mentioned. CRITICAL: For times 1-11 without AM/PM, assume MORNING (saat 9 -> 09:00, not 21:00). Only use PM/evening if explicitly stated. Convert: 7pm -> 19:00, 10am -> 10:00, saat 9 -> 09:00, akşam 7 -> 19:00. Time words: morning/sabah -> 08:00, evening/akşam -> 20:00, afternoon/öğleden sonra -> 14:00, noon/öğlen -> 12:00, night/gece -> 00:00. SPECIAL: 'tonight' or 'bu akşam' means evening time, use '20:00'. Return nil if no time.")
    let reminderTime: String?
}

actor ReminderParserService {
    static let shared = ReminderParserService()
    
    private let model: SystemLanguageModel
    private let instructions: Instructions
    
    private static func currentDateTimeContext() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' HH:mm"
        return "Current date and time: \(formatter.string(from: Date()))"
    }
    
    init() {
        self.model = SystemLanguageModel.default
        self.instructions = Instructions(
            """
            Parse reminder information from user input in ANY language. Extract reminder object, day, and time.
            
            RULES:
            - object: Reminder name only, lowercase with underscores. REMOVE temporal words.
            - reminderDay: today, tomorrow, monday-sunday, or date. English.
            - reminderTime: 24-hour HH:MM.
            
            EXAMPLES:
            - "Call mom tomorrow at 3pm" -> object: "call_mom", reminderDay: "tomorrow", reminderTime: "15:00"
            - "Buy groceries on friday" -> object: "buy_groceries", reminderDay: "friday"
            - "Pay rent 1st of month" -> object: "pay_rent", reminderDay: "1 dec"
            """
        )
    }
    
    func parse(text: String, originalText _: String) async -> (object: String, reminderDay: String?, reminderTime: String?) {
        guard model.availability == .available else {
            return (object: text, reminderDay: nil, reminderTime: nil)
        }

        do {
            let contextualPrompt = "\(Self.currentDateTimeContext())\nUser input: \(text)"
            let prompt = Prompt(contextualPrompt)
            let session = LanguageModelSession(instructions: instructions)

            let response = try await session.respond(generating: ReminderParsedEntry.self, includeSchemaInPrompt: true, options: GenerationOptions(), prompt: { prompt })
            return (response.content.object, response.content.reminderDay, response.content.reminderTime)
        } catch is LanguageModelSession.GenerationError {
            return (object: text, reminderDay: nil, reminderTime: nil)
        } catch {
            return (object: text, reminderDay: nil, reminderTime: nil)
        }
    }
}
