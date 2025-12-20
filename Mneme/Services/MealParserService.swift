import Foundation
import FoundationModels

@Generable(description: "Parsed meal entry")
struct MealParsedEntry {
    @Guide(description: "Food name ONLY. Do NOT include quantity/weight units (e.g., '100g', '250g') in the food name. If input is 'pizza 100g', extract 'pizza' not 'pizza100g'. Include ALL modifiers that are part of the food name: menu/combo/meal/set indicators (in ANY language: menu, menü, menú, etc.) and size indicators (in ANY language: large, büyük, grande, etc.). These modifiers are PART OF THE FOOD NAME, NOT quantity. Examples: 'big mac menu' -> 'big_mac_menu', 'big mac menü büyük' -> 'big_mac_menu_buyuk'. For MULTIPLE meals separated by '+' or 'and': use '_+_' separator (e.g., 'ate pizza + kokoreç' -> 'pizza_+_kokorec'). Use lowercase with underscores. CRITICAL: The food name MUST match the original input (after removing quantity/units). Do NOT change the food name to something different. If the input is about a social event with food (e.g., 'dinner with John'), extract the food name from the event (e.g., 'dinner'), but this should rarely happen as such inputs should be classified as 'event' intent, not 'meal'.")
    let object: String
    
    @Guide(description: "Meal quantity WITH portion descriptors. MUST include portion words like 'dilim' (slice), 'tabak' (plate), 'porsiyon' (serving), 'fincan' (cup), 'bardak' (glass), 'büyük' (large), 'küçük' (small) etc. Examples: '1 dilim' (1 slice), '2 tabak' (2 plates), '1 büyük' (1 large), '100g' (100 grams), '250ml'. CRITICAL: Preserve portion descriptors - they are needed for gram conversion. If input is '1 dilim pizza', extract '1 dilim' NOT just '1'. If no quantity specified, leave as nil.")
    let mealQuantity: String?
    
    @Guide(description: "Whether this is a fast food brand menu/combo/meal. True ONLY for fast food brand menus (Big Mac Menu, Whopper Combo, Quarter Pounder Meal, etc.). False for general foods (pizza, kokoreç, apple, etc.) even if they have size modifiers like 'large pizza' or 'büyük pizza'. Size modifiers alone do NOT make something a menu. A menu is a complete fast food meal (burger/sandwich + fries + drink) from a fast food brand.")
    let isMenu: Bool
    
    @Guide(description: "Meal calories ONLY if user explicitly typed it in the input (e.g., 'pizza 500kcal', 'ate burger 800 calories'). DO NOT estimate, guess, or calculate calories. If user did not type a calorie number, leave as nil. Examples: 'pizza 300kcal' → 300.0, '1 dilim pizza' → nil, 'burger' → nil, 'ate 500 calorie meal' → 500.0")
    let mealKcal: Double?
}

actor MealParserService {
    static let shared = MealParserService()
    
    private let model: SystemLanguageModel
    private let instructions: Instructions
    
    init() {
        self.model = SystemLanguageModel.default
        self.instructions = Instructions("""
        Parse meal information from user input in ANY language (Turkish, English, French, Spanish, German, Italian, Portuguese, etc.). The LLM supports multilingual input natively. Extract food name, quantity, calories, and determine if it's a fast food menu.
        
        CRITICAL RULES:
        - object: Extract food name ONLY. Remove quantity/weight units. Include menu/combo/meal/set and size modifiers as part of food name. For multiple meals separated by '+' (e.g., "100g pizza + 100g kokoreç"), return the FULL RAW STRING including quantities (e.g., "100g pizza + 100g kokoreç") and set mealQuantity to nil. This allows the downstream service to split and parse them individually. The food name MUST match the original input (after removing quantity/units). Preserve original language for food names (e.g., "kokoreç" -> "kokorec", "döner" -> "doner", "croissant" -> "croissant")
        - mealQuantity: Extract quantity WITH portion descriptors (dilim, tabak, porsiyon, fincan, bardak, büyük, küçük, slice, plate, cup, large, small) OR bare numbers before the food name (e.g., "2 hamburger" -> mealQuantity: "2"). Preserve portion words; bare numbers are still valid quantities. Examples: "1 dilim", "2 tabak", "1 büyük", "100g", "250ml", "2".
        - isMenu: True ONLY for fast food brand menus (Big Mac Menu, Whopper Combo, etc.). False for general foods (pizza, kokoreç, apple) even with size modifiers. Size modifiers alone do NOT make something a menu.
        - mealKcal: ONLY if user explicitly typed calorie number. DO NOT estimate. Examples: "pizza 300kcal" → 300, "1 dilim pizza" → nil, "burger" → nil. Leave nil if user didn't type calories.
        
        EXAMPLES:
        - "100g pizza" -> object: "pizza", mealQuantity: "100g", isMenu: false, mealKcal: nil
        - "1 dilim pizza" -> object: "pizza", mealQuantity: "1 dilim", isMenu: false, mealKcal: nil
        - "2 tabak pilav" -> object: "pilav", mealQuantity: "2 tabak", isMenu: false, mealKcal: nil
        - "1 büyük pizza" -> object: "pizza", mealQuantity: "1 büyük", isMenu: false, mealKcal: nil
        - "pizza 500kcal" -> object: "pizza", mealQuantity: nil, isMenu: false, mealKcal: 500.0
        - "big mac menu" -> object: "big_mac_menu", mealQuantity: nil, isMenu: true, mealKcal: nil
        - "büyük pizza" -> object: "buyuk_pizza", mealQuantity: nil, isMenu: false, mealKcal: nil (no quantity number)
        - "big mac menü büyük" -> object: "big_mac_menu_buyuk", mealQuantity: nil, isMenu: true, mealKcal: nil
        - "kokoreç 200g" -> object: "kokorec", mealQuantity: "200g", isMenu: false, mealKcal: nil
        - "j'ai mangé une pizza" -> object: "pizza", mealQuantity: nil, isMenu: false, mealKcal: nil
        - "1 slice of pizza" -> object: "pizza", mealQuantity: "1 slice", isMenu: false, mealKcal: nil
        - "2 cups of coffee" -> object: "coffee", mealQuantity: "2 cups", isMenu: false, mealKcal: nil
        - "2 hamburger" -> object: "hamburger", mealQuantity: "2", isMenu: false, mealKcal: nil
        - "ate burger 800 calories" -> object: "burger", mealQuantity: nil, isMenu: false, mealKcal: 800.0
        """)
    }
    
    func parse(text: String) async throws -> (object: String, mealQuantity: String?, isMenu: Bool, mealKcal: Double?) {
        guard model.availability == .available else {
            return (object: text, mealQuantity: nil, isMenu: false, mealKcal: nil)
        }
        
        do {
            let prompt = Prompt(text)
            let session = LanguageModelSession(instructions: instructions)
            
            let response = try await session.respond(
                generating: MealParsedEntry.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(),
                prompt: { prompt }
            )
            
            let parsed = response.content
            
            // Minimal validation: check if quantity contains food name (likely mistake)
            var mealQuantity = parsed.mealQuantity
            if let quantity = mealQuantity {
                let normalizedQuantity = quantity.lowercased().replacingOccurrences(of: " ", with: "_")
                let normalizedObject = parsed.object.lowercased()
                if normalizedQuantity == normalizedObject || normalizedQuantity.contains(normalizedObject) {
                    mealQuantity = nil
                }
            }
            
            // Fallback: bare number before food (e.g., "2 hamburger")
            if mealQuantity == nil {
                if let number = TextParsingHelpers.extractFirstNumber(from: text) {
                    // Represent as plain string to keep downstream handling intact
                    if floor(number) == number {
                        mealQuantity = String(format: "%.0f", number)
                    } else {
                        mealQuantity = String(number)
                    }
                }
            }
            
            return (parsed.object, mealQuantity, parsed.isMenu, parsed.mealKcal)
            
        } catch let error as LanguageModelSession.GenerationError {
            throw error
        } catch {
            throw error
        }
    }
}
