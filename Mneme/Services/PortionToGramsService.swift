import Foundation
import FoundationModels

@Generable(description: "Portion to grams conversion result")
struct PortionConversion {
    @Guide(description: "Estimated grams for the portion. Use typical/average values. Examples: 1 slice pizza ≈ 120g, 1 plate rice ≈ 200g, 1 cup milk ≈ 240g, 1 tablespoon oil ≈ 15g, 1 large pizza ≈ 900g, 1 medium apple ≈ 180g. Be realistic and consider the food type.")
    let grams: Double
    
    @Guide(description: "Brief explanation of the conversion reasoning (e.g., 'typical pizza slice', 'standard dinner plate', 'large size estimate').")
    let reasoning: String
}

nonisolated final class PortionToGramsService {
    nonisolated(unsafe) static let shared = PortionToGramsService()
    
    private nonisolated let model: SystemLanguageModel
    private nonisolated let instructions: Instructions
    
    nonisolated init() {
        self.model = SystemLanguageModel.default
        self.instructions = Instructions("""
        Convert food portions/servings to grams. You are an expert nutritionist with deep knowledge of typical food portion sizes across different cuisines and cultures.
        
        MULTILINGUAL SUPPORT:
        - You understand portion descriptors in ANY language (Turkish, English, French, Italian, Spanish, German, Japanese, Chinese, etc.)
        - Examples: "1 dilim" (Turkish), "une tranche" (French), "una fetta" (Italian), "一切れ" (Japanese)
        - Extract portion information regardless of language
        
        CRITICAL RULES:
        - Use REALISTIC portion sizes based on the food type
        - Consider cultural context (Turkish, American, European portions differ)
        - Account for size modifiers in any language (large, büyük, grande, groß, etc.)
        - Be consistent with similar foods
        
        COMMON CONVERSIONS (use as reference):
        
        **Slices (dilim)**:
        - Pizza slice: 120g (1/8 of medium pizza)
        - Bread slice: 30g (standard loaf)
        - Cake slice: 80g (typical serving)
        - Cheese slice: 20g (thin slice)
        
        **Plates (tabak)**:
        - Rice/pilaf: 200g (standard dinner plate)
        - Pasta: 180g (cooked, standard serving)
        - Salad: 150g (side salad)
        - Yogurt: 200g (typical bowl)
        - Soup: 250ml (standard bowl)
        
        **Portions (porsiyon)**:
        - Meat: 150g (standard protein serving)
        - Fish: 180g (fillet)
        - Chicken breast: 200g (medium)
        - Kokoreç: 150g (standard wrap)
        
        **Cups (fincan/bardak)**:
        - Milk: 240ml = 240g
        - Coffee: 180ml = 180g
        - Rice (uncooked): 185g
        - Water: 240ml = 240g
        
        **Size modifiers**:
        - Small/küçük: 0.7x normal
        - Medium/orta: 1.0x normal
        - Large/büyük: 1.5x normal
        - Extra large: 2.0x normal
        
        **Whole items**:
        - Pizza (whole): 800-1000g depending on size
        - Apple: 180g (medium)
        - Banana: 120g (medium)
        - Egg: 50g
        - Burger: 200-250g (including bun)
        
        **Turkish cuisine specifics**:
        - Lahmacun: 150g (standard)
        - Pide: 300g (1 person)
        - Dürüm: 250g (wrap with filling)
        - Simit: 100g
        - Börek (slice): 120g
        
        EXAMPLES:
        - "1 slice pizza" → 120g (typical pizza slice)
        - "1 plate rice" → 200g (standard dinner plate)
        - "2 slices bread" → 60g (2 × 30g standard slices)
        - "1 large pizza" → 1200g (family size)
        - "1 tabak pilav" → 200g (Turkish standard portion)
        - "1 cup coffee" → 180g (standard cup)
        - "half apple" → 90g (half of 180g medium apple)
        """)
    }
    
    nonisolated func convertToGrams(foodName: String, quantity: String) async -> (grams: Double, reasoning: String)? {
        guard model.availability == .available else {
            return nil
        }
        
        if let existingGrams = extractExistingGrams(from: quantity) {
            return (existingGrams, "explicit gram value")
        }
        
        do {
            let session = LanguageModelSession(instructions: instructions)
            let prompt = Prompt("Convert: \(quantity) \(foodName)")
            
            let response = try await session.respond(
                generating: PortionConversion.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(),
                prompt: { prompt }
            )
            
            let conversion = response.content
            return (conversion.grams, conversion.reasoning)
        } catch {
            return nil
        }
    }
    
    private nonisolated func extractExistingGrams(from text: String) -> Double? {
        let pattern = #"(\d+(?:\.\d+)?)\s*(?:g|gram|grams|gr)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[range])
    }
}
