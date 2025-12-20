import Foundation
import FoundationModels

@Generable(description: "Parsed event entry")
struct EventParsedEntry {
    @Guide(description: "Event name/title. Extract the actual event name (e.g., 'dinner with tugce' -> 'dinner_with_tugce', 'doctor appointment' -> 'doctor_appointment', 'team meeting' -> 'team_meeting'). Use lowercase with underscores.")
    let object: String
    
    @Guide(description: "Event day: today, tomorrow, monday-sunday, next_monday-next_sunday, or date formats like '22 nov', 'november 22'. If 'next week' without specific day, use 'next_monday'. SPECIAL: 'tonight' or 'bu akşam' means today, so use 'today'.")
    let eventDay: String?
    
    @Guide(description: "Event time in 24-hour HH:MM format. ONLY if explicitly mentioned. CRITICAL: For times 1-11 without AM/PM, assume MORNING (saat 9 -> 09:00, not 21:00). Only use PM/evening if explicitly stated. Convert: 7pm -> 19:00, 10am -> 10:00, saat 9 -> 09:00, akşam 7 -> 19:00, 19h -> 19:00. Time words: morning/sabah -> 08:00, evening/akşam -> 20:00, afternoon/öğleden sonra -> 14:00, noon/öğlen -> 12:00, night/gece -> 00:00. SPECIAL: 'tonight' or 'bu akşam' means evening time, use '20:00'. Return nil if no time.")
    let eventTime: String?
}

actor EventParserService {
    static let shared = EventParserService()
    
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
            Parse event information from user input in ANY language. Extract event name, day, and time.
            
            RULES:
            - object: Event name only, lowercase with underscores. CLEANUP: Remove all temporal words from the name.
            - eventDay: today, tomorrow, monday-sunday, next_monday-next_sunday, or dates like "22 nov".
            - eventTime: 24-hour HH:MM format. ONLY if explicitly mentioned.
            
            EXAMPLES:
            - "Meeting tomorrow at 3pm" -> object: "meeting", eventDay: "tomorrow", eventTime: "15:00"
            - "Dinner with friends on friday" -> object: "dinner_with_friends", eventDay: "friday"
            - "Doctor appointment 22 nov 10am" -> object: "doctor_appointment", eventDay: "22 nov", eventTime: "10:00"
            """
        )
    }
    
    func parse(text: String, originalText _: String) async -> (object: String, eventDay: String?, eventTime: String?) {
        guard model.availability == .available else {
            return (object: text, eventDay: nil, eventTime: nil)
        }

        do {
            let contextualPrompt = "\(Self.currentDateTimeContext())\nUser input: \(text)"
            let prompt = Prompt(contextualPrompt)
            let session = LanguageModelSession(instructions: instructions)

            let response = try await session.respond(generating: EventParsedEntry.self, includeSchemaInPrompt: true, options: GenerationOptions(), prompt: { prompt })
            return (response.content.object, response.content.eventDay, response.content.eventTime)
        } catch is LanguageModelSession.GenerationError {
            return (object: text, eventDay: nil, eventTime: nil)
        } catch {
            return (object: text, eventDay: nil, eventTime: nil)
        }
    }
}
