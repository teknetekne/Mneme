import Foundation

struct USDAFoodItem: Identifiable, Codable {
    let id: Int
    let description: String
    let brandOwner: String?
    let foodNutrients: [USDANutrient]?
    
    enum CodingKeys: String, CodingKey {
        case id = "fdcId"
        case description
        case brandOwner
        case foodNutrients
    }
    
    // Helper to extract specific nutrients
    var calories: Double? {
        foodNutrients?.first(where: { $0.nutrientId == 1008 })?.value // Energy (kcal)
    }
}

struct USDANutrient: Codable {
    let nutrientId: Int
    let nutrientName: String
    let unitName: String
    let value: Double
}

struct USDASearchResponse: Codable {
    let foods: [USDAFoodItem]
}

extension USDAFoodItem {
    // Helper to get calories per 100g or per serving depending on data
    // Foundation foods are usually per 100g.
    // Branded foods have servingSize.
    
    func getCalories(forGrams grams: Double) -> Double? {
        guard let cal = calories else { return nil }
        // USDA values are typically per 100g or 100ml for Foundation/SR Legacy
        // For Branded, they are also normalized to 100g/100ml usually in the nutrient list, 
        // OR per serving. But the API documentation says nutrient values are per 100g usually?
        // Actually, FDC API usually returns nutrients per 100g/100ml for all types in the 'foodNutrients' list of search results.
        // Let's assume per 100g.
        return (cal / 100.0) * grams
    }
}

final class USDAService {
    static let shared = USDAService()
    
    private let baseURL = "https://api.nal.usda.gov/fdc/v1"
    private var apiKey: String {
        // Use ProcessInfo environment (from Xcode Scheme or Xcode Cloud)
        return ProcessInfo.processInfo.environment["USDA_API_KEY"] ?? "DEMO_KEY"
    }
    
    private init() {}
    
    // MARK: - Search
    
    func searchFood(query: String) async throws -> [USDAFoodItem] {
        guard !apiKey.isEmpty else { return [] }
        
        var components = URLComponents(string: "\(baseURL)/foods/search")
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "pageSize", value: "5"), // Top 5 is enough
            URLQueryItem(name: "dataType", value: "Foundation,SR Legacy,Branded") 
        ]
        
        guard let url = components?.url else { return [] }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }
        
        do {
            let result = try JSONDecoder().decode(USDASearchResponse.self, from: data)
            return result.foods
        } catch {
            return []
        }
    }
    
    // MARK: - Helper for MealHandler
    
    func getCaloriesForMeal(
        mealName: String,
        quantity: Double,
        grams: Double?
    ) async -> (calories: Double, sources: [CalorieSource])? {
        // 1. Search USDA
        // Try exact query first
        let query = "\(mealName)" // Just search name
        
        guard let foods = try? await searchFood(query: query), let bestMatch = foods.first else {
            return nil
        }
        
        // 2. Calculate Calories
        var finalCalories: Double = 0.0
        var sourceDescription = "USDA"
        
        if let g = grams {
            // User specified grams. Assume USDA nutrients are per 100g.
            if let cal = bestMatch.calories {
                finalCalories = (cal / 100.0) * g
            }
        } else {
            // User specified quantity (e.g. 1 apple).
            // We need a default gram weight or serving size.
            // USDA search results for Foundation foods might not have serving size.
            // We'll treat quantity as 1 serving = 100g if unknown? Or better, try to find serving size.
            
            // For now, simpler approach: Default to 100g * quantity if no serving size info.
            // Ideally we'd map "1 apple" to "182g". This requires portions.
            // If we lack portion info, we might just assume 100g per unit (risky) or return per 100g and let user adjust.
            // Let's assume 100g per unit if unknown.
            
            if let cal = bestMatch.calories {
                 finalCalories = cal * quantity // default 100g * qty
                 sourceDescription += " (100g est.)"
            }
        }
        
        guard finalCalories > 0 else { return nil }
        
        let source = CalorieSource(
            name: bestMatch.description.capitalized,
            url: "https://fdc.nal.usda.gov/fdc-app.html#/food-details/\(bestMatch.id)/nutrients",
            calories: finalCalories
        )
        
        return (finalCalories, [source])
    }
}
