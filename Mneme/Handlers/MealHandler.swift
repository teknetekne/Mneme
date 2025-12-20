import Foundation

/// Handler for meal-related intents
/// Responsible for portion-to-grams conversion and calorie fetching
/// Supports single meals, multi-meals (pizza + burger), and variable lookup
final class MealHandler: IntentHandler {
    private let usdaService = USDAService.shared
    private let portionService = PortionToGramsService.shared
    private let variableHandler = VariableHandler.shared
    
    func handle(
        result: ParsedResult,
        text: String,
        lineId: UUID
    ) async -> [ParsingResultItem] {
        var items: [ParsingResultItem] = []
        
        // 1. Add Intent
        items.append(intentItem())
        
        // 2. Extract meal name(s)
        guard let objectValue = result.object?.value else {
            return items + [errorItem("No meal name found")]
        }
        
        // 3. Check for multi-meal (pizza + burger)
        if objectValue.contains("_+_") {
            let multiMealItems = await handleMultiMeal(
                objectValue: objectValue,
                quantity: result.mealQuantity?.value,
                isMenu: result.mealIsMenu?.value ?? false,
                text: text
            )
            items.append(contentsOf: multiMealItems)
        } else {
            // Single meal
            let cleanedMealName = cleanMealName(objectValue, originalText: text)
            guard !cleanedMealName.isEmpty else {
                return items + [errorItem("Empty meal name")]
            }
            
            items.append(subjectItem(cleanedMealName))
            
            // Add quantity if present
            if let quantity = result.mealQuantity?.value {
                items.append(quantityItem(quantity))
            }
            
            // Convert portion to grams
            let grams = await convertToGrams(
                mealName: cleanedMealName,
                quantity: result.mealQuantity?.value,
                isMenu: result.mealIsMenu?.value ?? false
            )
            
            // Fetch calories
            let calorieItems = await fetchCaloriesForMeal(
                mealName: cleanedMealName,
                quantity: result.mealQuantity?.value,
                grams: grams
            )
            items.append(contentsOf: calorieItems)
        }
        
        return items
    }
    
    // MARK: - Conversion Logic
    
    /// Convert portion descriptors to grams using LLM
    /// This is the CRITICAL step that fixes "grams: nil" issue
    private func convertToGrams(
        mealName: String,
        quantity: String?,
        isMenu: Bool
    ) async -> Double? {
        guard let quantity = quantity else {
            return nil
        }
        
        // Check for explicit grams (e.g., "200g", "150 gram")
        if let grams = TextParsingHelpers.extractGrams(from: quantity) {
            return grams
        }
        
        // Check if simple number (e.g., "2", "3.5")
        let trimmed = quantity.trimmingCharacters(in: .whitespaces)
        if Double(trimmed) != nil {
            // Try to get grams using LLM even for bare counts (e.g., "2 hamburger")
            if let conversion = await portionService.convertToGrams(
                foodName: mealName,
                quantity: trimmed
            ) {
                return conversion.grams
            }
            
            // Fallback: treat as count, let downstream calorie lookup handle quantity
            return nil
        }
        
        // Has portion descriptors (e.g., "1 dilim", "2 plates", "eine Scheibe")
        // Use LLM-based conversion - supports multilingual
        if let conversion = await portionService.convertToGrams(
            foodName: mealName,
            quantity: quantity
        ) {
            return conversion.grams
        }
        
        // Fallback: try to extract any number from the string
        if TextParsingHelpers.extractFirstNumber(from: quantity) != nil {
            return nil  // Return nil to use as quantity, not grams
        }
        
        return nil
    }
    
    // MARK: - Multi-Meal Handling
    
    private func handleMultiMeal(
        objectValue: String,
        quantity: String?,
        isMenu: Bool,
        text: String
    ) async -> [ParsingResultItem] {
        var items: [ParsingResultItem] = []
        
        let mealObjects = objectValue.components(separatedBy: "_+_")
            .map { $0.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        guard !mealObjects.isEmpty else {
            return [errorItem("No valid meals found")]
        }
        
        // Add subject with combined meals
        let displaySubject = mealObjects.map { $0.capitalized }.joined(separator: " + ")
        items.append(subjectItem(displaySubject))
        
        // Add quantity if present
        if let quantity = quantity {
            items.append(quantityItem(quantity))
        }
        
        let qty = Double(quantity ?? "1") ?? 1.0
        
        // Extract grams from quantity (e.g., "100g")
        var gramsValue: Double? = nil
        if let quantityStr = quantity?.lowercased() {
            if quantityStr.hasSuffix("g") {
                let numericPart = quantityStr.dropLast().trimmingCharacters(in: .whitespaces)
                gramsValue = Double(numericPart)
            }
        }
        
        var totalCalories: Double = 0.0
        var allFound = true
        var allSources: [CalorieSource] = []
        
        // Process each meal
        for mealName in mealObjects {
            let cleanedName = cleanMealName(mealName, originalText: text)
            guard !cleanedName.isEmpty else { continue }
            
            // Convert portion to grams for this meal
            let grams = await convertToGrams(
                mealName: cleanedName,
                quantity: quantity,
                isMenu: isMenu
            )
            
            // Try variable lookup first (with grams support)
            if let variableItems = variableHandler.handleMealVariable(
                mealName: cleanedName,
                quantity: qty,
                inputGrams: grams ?? gramsValue
            ), let variableItem = variableItems.first {
                // Extract calories from variable item
                let caloriesValue = variableItem.value.replacingOccurrences(of: " kcal", with: "")
                if let mealCalories = Double(caloriesValue) {
                    totalCalories += mealCalories
                    let capitalizedMealName = cleanedName.capitalized
                    
                    // Get variable info for source
                    if let variable = variableHandler.findVariable(for: cleanedName, type: .meal, intent: "meal") {
                        let variableSource = CalorieSource(
                            name: "Variable: \(variable.name)",
                            url: nil,
                            calories: mealCalories
                        )
                        
                        let sourcesJSON = encodeSources([variableSource])
                        items.append(ParsingResultItem(
                            field: "Calories - \(capitalizedMealName)",
                            value: variableItem.value,
                            isValid: true,
                            errorMessage: sourcesJSON,
                            rawValue: nil,
                            confidence: nil
                        ))
                        allSources.append(variableSource)
                    }
                }
            } else if let calorieResult = await usdaService.getCaloriesForMeal(
                mealName: cleanedName,
                quantity: qty,
                grams: grams ?? gramsValue
            ) {
                totalCalories += calorieResult.calories
                let capitalizedMealName = cleanedName.capitalized
                
                let sourcesJSON = encodeSources(calorieResult.sources)
                items.append(ParsingResultItem(
                    field: "Calories - \(capitalizedMealName)",
                    value: String(format: "%.0f kcal", calorieResult.calories),
                    isValid: true,
                    errorMessage: sourcesJSON,
                    rawValue: nil,
                    confidence: nil
                ))
                allSources.append(contentsOf: calorieResult.sources)
            } else {
                allFound = false
                let capitalizedMealName = cleanedName.capitalized
                items.append(ParsingResultItem(
                    field: "Calories - \(capitalizedMealName)",
                    value: "Not found",
                    isValid: false,
                    errorMessage: "Could not find calories for \(cleanedName)",
                    rawValue: nil,
                    confidence: nil
                ))
            }
        }
        
        // Add total calories
        if totalCalories > 0 {
            let totalSourcesJSON = encodeSources(allSources)
            items.append(ParsingResultItem(
                field: "Calories",
                value: String(format: "%.0f kcal", totalCalories),
                isValid: allFound,
                errorMessage: totalSourcesJSON,
                rawValue: nil,
                confidence: nil
            ))
        } else {
            items.append(ParsingResultItem(
                field: "Calories",
                value: "Not found",
                isValid: false,
                errorMessage: "Could not find calories for any meal",
                rawValue: nil,
                confidence: nil
            ))
        }
        
        return items
    }
    
    // MARK: - Single Meal Calorie Fetching
    
    private func fetchCaloriesForMeal(
        mealName: String,
        quantity: String?,
        grams: Double?
    ) async -> [ParsingResultItem] {
        var items: [ParsingResultItem] = []
        
        let qty = Double(quantity ?? "1") ?? 1.0
        
        // For bare counts with no grams, fetch a single-item calorie and multiply locally.
        // This avoids per-100g fallbacks returning only one portion.
        let serviceQty: Double = grams == nil ? 1.0 : qty
        
        // Try variable lookup first
        if let variableItems = variableHandler.handleMealVariable(
            mealName: mealName,
            quantity: qty,
            inputGrams: grams
        ) {
            return variableItems
        }
        
        // Fetch from USDA service
        if let result = await usdaService.getCaloriesForMeal(
            mealName: mealName,
            quantity: serviceQty,
            grams: grams
        ) {
            let adjustedCalories: Double
            if grams == nil {
                adjustedCalories = result.calories * qty  // scale by count
            } else {
                adjustedCalories = result.calories
            }
            
            let sourcesJSON = encodeSources(result.sources)
            items.append(ParsingResultItem(
                field: "Calories",
                value: String(format: "%.0f kcal", adjustedCalories),
                isValid: adjustedCalories > 0,
                errorMessage: sourcesJSON,
                rawValue: nil,
                confidence: nil
            ))
        } else {
            items.append(ParsingResultItem(
                field: "Calories",
                value: "Not found",
                isValid: false,
                errorMessage: "Could not find calories for this meal",
                rawValue: nil,
                confidence: nil
            ))
        }
        
        return items
    }
    
    // MARK: - Helper Methods
    
    private func cleanMealName(_ mealName: String, originalText: String) -> String {
        var cleaned = mealName.replacingOccurrences(of: "_", with: " ")
        
        cleaned = cleaned.replacingOccurrences(of: "+", with: "").trimmingCharacters(in: .whitespaces)
        
        let mealVerbs = ["had", "ate", "eating", "consumed", "finished", "having"]
        for verb in mealVerbs {
            if cleaned.lowercased().hasPrefix(verb + " ") {
                cleaned = String(cleaned.dropFirst(verb.count + 1))
            }
        }
        
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        
        if cleaned.isEmpty {
            cleaned = originalText.replacingOccurrences(of: "+", with: "").trimmingCharacters(in: .whitespaces)
        }
        
        let lowerCleaned = cleaned.lowercased()
        if mealVerbs.contains(lowerCleaned) {
            return ""
        }
        
        return cleaned
    }
    
    
    private func encodeSources(_ sources: [CalorieSource]) -> String? {
        guard let jsonData = try? JSONEncoder().encode(sources),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }
    
    // MARK: - Result Builders
    
    private func intentItem() -> ParsingResultItem {
        ParsingResultItem(
            field: "Intent",
            value: NotepadFormatter.formatIntentForDisplay("meal"),
            isValid: true,
            errorMessage: nil,
            confidence: nil
        )
    }
    
    private func subjectItem(_ name: String) -> ParsingResultItem {
        ParsingResultItem(
            field: "Subject",
            value: name.capitalized,
            isValid: true,
            errorMessage: nil,
            confidence: nil
        )
    }
    
    private func quantityItem(_ quantity: String) -> ParsingResultItem {
        ParsingResultItem(
            field: "Meal Quantity",
            value: quantity,
            isValid: true,
            errorMessage: nil,
            confidence: nil
        )
    }
    
    private func calorieItem(_ calories: Double) -> ParsingResultItem {
        ParsingResultItem(
            field: "Calories",
            value: "\(Int(calories)) kcal",
            isValid: true,
            errorMessage: nil,
            confidence: nil
        )
    }
    
    private func errorItem(_ message: String) -> ParsingResultItem {
        ParsingResultItem(
            field: "Error",
            value: message,
            isValid: false,
            errorMessage: message,
            confidence: nil
        )
    }
}
