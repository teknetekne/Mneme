import Foundation
import FoundationModels

@Generable(description: "Intent classification for notepad entry")
struct IntentClassification {
    @Guide(description: "Intent type: meal, expense, income, reminder, event, activity, work_start, work_end, calorie_adjustment, journal, or 'none' if no intent detected")
    let intent: String
}

actor IntentClassificationService {
    static let shared = IntentClassificationService()
    
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
            Classify the intent of user input in ANY language (Turkish, English, French, Spanish, German, Italian, Portuguese, etc.). The LLM supports multilingual input natively. Return ONLY the intent type.
            
            INTENTS:
            - meal: Eating food - ONLY for food consumption logging, including fast food menus (e.g., "ate pizza", "pizza 100g", "Big Mac menü", "Whopper meal", "McChicken menu", "yedim pizza", "pizza yedim", "chicken breast 200g", "tavuk göğsü 200g", "1 dilim ekmek", "2 yumurta"). ANY food item with quantity/weight/portion MUST be classified as MEAL, NOT EVENT.
            - expense: Spending money (e.g., "spent 50 USD", "bought coffee", "paid 20 dollars", "50 dolar harcadım", "kahve aldım")
            - income: Receiving money (e.g., "got 1000 USD", "received salary", "earned 500", "1000 dolar aldım", "maaş aldım")
            - reminder: Task reminder (e.g., "remind me to call", "remember doctor", "don't forget meeting", "doktoru hatırlat", "arama yapmayı unutma")
            - event: Calendar event - meetings, appointments, social gatherings (e.g., "meeting tomorrow", "doctor appointment friday", "dinner with John tonight", "yarın toplantı", "cuma doktor randevusu", "bu akşam John ile akşam yemeği", "yarın spor yapacağım", "will go to gym tomorrow")
            - activity: Physical exercise LOGGING (e.g., "ran 5km", "walked 30 minutes", "cycling 10km", "5 km koştum", "30 dakika yürüdüm", "gym yaptı", "antrenman bitti"). CRITICAL: If the input refers to a FUTURE exercise (e.g. "I will run later", "yarım saat sonra spor", "akşam yürüyüş yapacağım"), it is an EVENT or REMINDER, NOT an activity.
            - work_start: Starting work session (e.g., "started working", "work begin", "clocked in", "işe başladım", "çalışmaya başladım")
            - work_end: Ending work session (e.g., "finished working", "work done", "clocked out", "işi bitirdim", "çalışmayı bitirdim")
            - calorie_adjustment: Manual calorie adjustment (e.g., "+100 kcal", "-50 calories", "+100 kalori")
            - journal: Personal diary/mood entry starting with mood emoji (😢😕😐🙂😊) followed by text (e.g., "😊 great day today", "😢 feeling down", "🙂 had a nice lunch")
            - none: No clear intent
            
            CRITICAL: If text starts with one of these mood emojis (😢😕😐🙂😊), it's ALWAYS a journal entry.
            
            CRITICAL: Food WITH people = EVENT (e.g., "dinner with X", "lunch with Y", "X ile akşam yemeği"). Food alone (even with quantity) = MEAL.
            """
        )
    }
    
    func classify(text: String) async -> String {
        guard model.availability == .available else {
            return "none"
        }
        
        do {
            let contextualPrompt = "\(Self.currentDateTimeContext())\nUser input: \(text)"
            let prompt = Prompt(contextualPrompt)
            let session = LanguageModelSession(instructions: instructions)
            
            let response = try await session.respond(generating: IntentClassification.self, includeSchemaInPrompt: true, options: GenerationOptions(), prompt: { prompt })
            
            return response.content.intent.lowercased()
        } catch {
            return "none"
        }
    }
}

