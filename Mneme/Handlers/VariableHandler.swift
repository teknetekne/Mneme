import Foundation

final class VariableHandler {
    private let variableStore = VariableStore.shared
    
    static let shared = VariableHandler()
    
    private init() {}
    
    func findVariable(
        for objectName: String,
        type: VariableType,
        intent: String? = nil
    ) -> VariableStruct? {
        let cleanedName = cleanObjectName(objectName)
        let variables = VariableStore.getVariablesSnapshot()
        
        return variables.first { variable in
            let variableName = variable.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = variableName == cleanedName && variable.type == type
            
            if let intent = intent {
                switch type {
                case .expense, .income:
                    return matches && (intent == "expense" && variable.type == .expense || intent == "income" && variable.type == .income)
                case .meal:
                    return matches && intent == "meal"
                }
            }
            
            return matches
        }
    }
    
    func handleMealVariable(
        mealName: String,
        quantity: Double
    ) -> [ParsingResultItem]? {
        guard let variable = findVariable(for: mealName, type: .meal, intent: "meal") else {
            return nil
        }
        
        // Use stored calories and grams if available
        if let storedCalories = variable.calories {
            let totalCalories: Double
            
            if let storedGrams = variable.grams, storedGrams > 0 {
                // Scaling logic: (InputGrams / StoredGrams) * StoredCalories
                // But wait, 'quantity' here is usually a multiplier (e.g. 2 pizzas) or grams if extracted elsewhere.
                // In MealHandler, 'quantity' passed here is usually the multiplier (qty).
                // If the user typed "200g pizza", MealHandler might pass quantity=200 if it thinks it's a number,
                // OR it might pass nil and handle grams separately.
                // Let's look at MealHandler usage.
                // MealHandler calls: variableHandler.handleMealVariable(mealName: mealName, quantity: qty)
                // where qty is Double(quantity ?? "1") ?? 1.0.
                // So 'quantity' is the multiplier.
                
                // If the user wants to specify grams for a variable (e.g. "200g pizza"),
                // MealHandler should handle that.
                // Currently MealHandler calculates 'grams' separately.
                // We should probably update handleMealVariable to accept 'grams' as well.
                
                totalCalories = storedCalories * quantity
            } else {
                // Simple multiplier
                totalCalories = storedCalories * quantity
            }
            
            return [
                ParsingResultItem(
                    field: "Calories",
                    value: String(format: "%.0f kcal", totalCalories),
                    isValid: true,
                    errorMessage: nil,
                    rawValue: nil,
                    confidence: nil
                )
            ]
        }
        
        return nil
    }
    
    // New method to handle grams input for variables
    func handleMealVariable(
        mealName: String,
        quantity: Double, // Multiplier
        inputGrams: Double? // Explicit grams from input
    ) -> [ParsingResultItem]? {
        guard let variable = findVariable(for: mealName, type: .meal, intent: "meal") else {
            return nil
        }
        
        if let storedCalories = variable.calories {
            var totalCalories: Double = 0
            
            if let inputGrams = inputGrams, let storedGrams = variable.grams, storedGrams > 0 {
                // Scale based on grams: (Input / Stored) * Calories
                totalCalories = (inputGrams / storedGrams) * storedCalories
            } else {
                // Fallback to multiplier
                totalCalories = storedCalories * quantity
            }
            
            return [
                ParsingResultItem(
                    field: "Calories",
                    value: String(format: "%.0f kcal", totalCalories),
                    isValid: true,
                    errorMessage: nil,
                    rawValue: nil,
                    confidence: nil
                )
            ]
        }
        
        return nil
    }
    
    func handleExpenseIncomeVariable(
        objectName: String,
        intent: String,
        currency: String?,
        baseCurrency: String
    ) -> ParsingResultItem? {
        let variableType: VariableType = intent == "expense" ? .expense : .income
        guard let variable = findVariable(for: objectName, type: variableType, intent: intent),
              let variableAmount = variable.amount ?? Double(variable.value) else {
            return nil
        }
        
        let sign = intent == "expense" ? "-" : "+"
        let finalCurrency = variable.currency ?? currency ?? baseCurrency
        
        return ParsingResultItem(
            field: "Amount",
            value: String(format: "%@%.2f %@", sign, variableAmount, finalCurrency),
            isValid: variableAmount != 0,
            errorMessage: variableAmount == 0 ? "Amount cannot be zero" : nil,
            confidence: nil
        )
    }
    
    func evaluateExpression(_ text: String, baseCurrency: String) -> ParsingResultItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if text contains operators (+ or -)
        // Must contain at least one operator to be an expression
        let hasOperator = trimmed.contains("+") || trimmed.contains("-")
        guard hasOperator else { return nil }
        
        // Normalize: if doesn't start with +/-, prepend + to first term
        var normalizedText = trimmed
        if !normalizedText.hasPrefix("+") && !normalizedText.hasPrefix("-") {
            normalizedText = "+" + normalizedText
        }
        
        // Regex to find operators and terms
        // Pattern: ([+-]) followed by anything until next [+-] or end
        let pattern = "([+-])\\s*([^+-]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        
        let nsString = normalizedText as NSString
        let matches = regex.matches(in: normalizedText, options: [], range: NSRange(location: 0, length: nsString.length))
        
        guard !matches.isEmpty else { return nil }
        
        var totalAmount: Double = 0
        var totalCalories: Double = 0
        var isCalorieCalculation = false
        var currency: String? = nil
        var validTermsCount = 0
        
        for match in matches {
            let operatorRange = match.range(at: 1)
            let termRange = match.range(at: 2)
            
            let op = nsString.substring(with: operatorRange)
            let rawTerm = nsString.substring(with: termRange).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // 1. Extract Quantities (Grams, Distance)
            let grams = TextParsingHelpers.extractGrams(from: rawTerm)
            let distance = UnitConversionHelper.parseDistance(from: rawTerm)
            
            // 2. Clean Term Name (remove quantity strings)
            var cleanTerm = rawTerm
            if grams != nil {
                // Remove "100g" etc.
                cleanTerm = removeQuantityString(from: cleanTerm)
            }
            if distance != nil {
                cleanTerm = removeQuantityString(from: cleanTerm)
            }
            
            cleanTerm = cleanObjectName(cleanTerm)
            
            // 3. Resolve Variable
            var termValue: Double? = nil
            var termIsCalories = false
            
            if let variable = findVariable(for: cleanTerm, type: .meal) ?? findVariable(for: cleanTerm, type: .expense) ?? findVariable(for: cleanTerm, type: .income) {
                // Variable Found
                if variable.type == .meal {
                    termIsCalories = true
                    if let cal = variable.calories {
                        if let g = grams, let storedGrams = variable.grams, storedGrams > 0 {
                            termValue = (g / storedGrams) * cal
                        } else {
                            termValue = cal // Default to 1 unit if no grams specified or stored
                        }
                    }
                } else {
                    // Money
                    if let amt = variable.amount ?? Double(variable.value) {
                        termValue = amt
                        if currency == nil { currency = variable.currency }
                    }
                }
            } else {
                // Variable NOT Found
                
                // If the term has explicit grams but no matching variable,
                // it's likely a generic food item (e.g. "+100g beef").
                // We should NOT parse "100" as a financial amount.
                // Let other handlers (MealHandler) process this.
                if grams != nil {
                    continue
                }

                // Check for Activity (Distance)
                if let dist = distance {
                    // Calculate Activity Calories
                    let weight = UserSettingsStore.shared.weight ?? 70.0 // Default 70kg
                    if let burned = UnitConversionHelper.calculateActivityCalories(distanceKm: dist.value, durationHours: nil, activityType: cleanTerm, weightKg: weight) {
                        termValue = burned
                        termIsCalories = true
                    } else {
                        // Found distance unit but couldn't calculate calories (e.g. unknown activity)
                        // This should NOT be treated as money.
                        continue
                    }
                } else {
                    // Try to extract number even if it has currency/unit
                    if let val = TextParsingHelpers.extractFirstNumber(from: rawTerm) {
                        termValue = val
                        
                        // Check for calorie units first
                        let loweredTerm = rawTerm.lowercased()
                        if loweredTerm.contains("kcal") || loweredTerm.contains("cal") {
                             termIsCalories = true
                        }
                        // Then check for currency if not calories
                        else if let extractedCurrency = TextParsingHelpers.extractCurrency(from: rawTerm) {
                            if currency == nil { currency = extractedCurrency }
                        }
                        
                        // Assume same type as previous terms or default?
                        if isCalorieCalculation {
                            termIsCalories = true
                        }
                    } else if let val = Double(cleanTerm) {
                        // Fallback simple number parsing
                         termValue = val
                         if isCalorieCalculation {
                             termIsCalories = true
                         }
                    }
                }
            }
            
            if let val = termValue {
                validTermsCount += 1
                if termIsCalories {
                    isCalorieCalculation = true
                    // If it is an activity (distance was parsed), it BURNS calories.
                    // So "+ 10km run" means SUBTRACT calories.
                    if distance != nil {
                        totalCalories += (op == "+" ? -val : val)
                    } else {
                        // Food adds calories
                        totalCalories += (op == "+" ? val : -val)
                    }
                } else {
                    totalAmount += (op == "+" ? val : -val)
                }
            } else {
                // Failed to resolve term
                return nil
            }
        }
        
        guard validTermsCount > 0 else { return nil }
        
        if isCalorieCalculation {
            // Return calorie result
            return ParsingResultItem(
                field: "Calories",
                value: String(format: "%@%.0f kcal", totalCalories >= 0 ? "+" : "", totalCalories),
                isValid: true,
                errorMessage: nil,
                confidence: 1.0
            )
        } else {
            // Return money result
            let finalCurrency = currency ?? baseCurrency
            return ParsingResultItem(
                field: "Amount",
                value: String(format: "%@%.2f %@", totalAmount >= 0 ? "+" : "", totalAmount, finalCurrency),
                isValid: true,
                errorMessage: nil,
                confidence: 1.0
            )
        }
    }
    
    private func cleanObjectName(_ name: String) -> String {
        return name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func removeQuantityString(from text: String) -> String {
        // Remove patterns like "100g", "1.5 km", "200 grams"
        // This is a heuristic cleanup
        let pattern = #"\d+(?:\.\d+)?\s*(?:g|gram|grams|gr|kg|kilogram|kilograms|oz|ounce|ounces|lb|lbs|pound|pounds|km|m|mile|miles)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        let range = NSRange(location: 0, length: text.utf16.count)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

