import Foundation

// MARK: - Simple Text Parsing Helpers
// Lightweight helpers for simple text extraction tasks

nonisolated struct TextParsingHelpers {
    // Extract first numeric value from text (supports "." or "," decimal separators)
    nonisolated static func extractFirstNumber(from text: String) -> Double? {
        let pattern = #"[-+]?\d+(?:[.,]\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 1 else {
            return nil
        }
        let token = ns.substring(with: match.range(at: 0))
        let normalized = token.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }
    
    // Extract weight in grams from text (supports g, kg, oz, lbs)
    nonisolated static func extractGrams(from text: String) -> Double? {
        // Pattern matches number followed by unit
        let pattern = #"(\d+(?:\.\d+)?)\s*(g|gram|grams|gr|kg|kilogram|kilograms|oz|ounce|ounces|lb|lbs|pound|pounds)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 3 else {
            return nil
        }
        
        let valueRange = match.range(at: 1)
        let unitRange = match.range(at: 2)
        
        guard valueRange.location != NSNotFound, unitRange.location != NSNotFound else { return nil }
        
        let valueStr = ns.substring(with: valueRange).replacingOccurrences(of: ",", with: ".")
        let unitStr = ns.substring(with: unitRange).lowercased()
        
        guard let value = Double(valueStr) else { return nil }
        
        // Convert to grams
        if unitStr.starts(with: "k") { // kg, kilogram
            return value * 1000.0
        } else if unitStr == "oz" || unitStr.contains("ounce") {
            return value * 28.3495
        } else if unitStr == "lb" || unitStr.contains("pound") || unitStr == "lbs" {
             return value * 453.592
        } else {
            // grams
            return value
        }
    }
    
    // Extract currency code from text (simple detection)
    nonisolated static func extractCurrency(from text: String) -> String? {
        let lowered = text.lowercased()
        
        // Check for currency symbols
        if lowered.contains("$") || lowered.contains("usd") || lowered.contains("dollar") {
            return "USD"
        }
        if lowered.contains("€") || lowered.contains("eur") || lowered.contains("euro") {
            return "EUR"
        }
        if lowered.contains("₺") || lowered.contains("try") || lowered.contains("turkish lira") || lowered.contains("lira") {
            return "TRY"
        }
        if lowered.contains("£") || lowered.contains("gbp") || lowered.contains("pound") {
            return "GBP"
        }
        
        // Check for 3-letter currency codes
        let codePattern = #"\b([a-z]{3})\b"#
        if let regex = try? NSRegularExpression(pattern: codePattern, options: .caseInsensitive) {
            let ns = lowered as NSString
            let range = NSRange(location: 0, length: ns.length)
            let matches = regex.matches(in: lowered, options: [], range: range)
            
            for match in matches {
                guard match.numberOfRanges >= 2 else { continue }
                let codeRange = match.range(at: 1)
                guard codeRange.location != NSNotFound else { continue }
                
                let code = ns.substring(with: codeRange).uppercased()
                let validCodes = ["USD", "EUR", "TRY", "GBP", "JPY", "CNY", "CAD", "AUD"]
                if validCodes.contains(code) {
                    return code
                }
            }
        }
        
        return nil
    }
    
    // Parse multiple income/expense adjustments from text
    // Returns array of (amount, currency) tuples
    nonisolated static func parseAdjustments(from text: String) -> [(amount: Double, currency: String)] {
        var adjustments: [(amount: Double, currency: String)] = []
        let lowered = text.lowercased()
        
        // Pattern: +amount currency or -amount currency
        let pattern = #"([+-])\s*(\d+(?:\.\d+)?)\s*([a-z]{3}|usd|eur|try|gbp|tl|\$|€|₺|£)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return adjustments
        }
        
        let ns = lowered as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: lowered, options: [], range: range)
        
        for match in matches {
            guard match.numberOfRanges >= 4 else { continue }
            
            let signRange = match.range(at: 1)
            let amountRange = match.range(at: 2)
            let currencyRange = match.range(at: 3)
            
            guard signRange.location != NSNotFound,
                  amountRange.location != NSNotFound,
                  currencyRange.location != NSNotFound else {
                continue
            }
            
            let sign = ns.substring(with: signRange)
            let amountStr = ns.substring(with: amountRange)
            let currencyText = ns.substring(with: currencyRange)
            let normalizedAmount = amountStr.replacingOccurrences(of: ",", with: ".")
            guard let amount = Double(normalizedAmount) else { continue }
            guard let currency = normalizeCurrencyCode(currencyText) else { continue }
            
            let finalAmount = sign == "+" ? amount : -amount
            adjustments.append((amount: finalAmount, currency: currency))
        }
        
        return adjustments
    }

    // Detect net calorie adjustments from simple arithmetic expressions (e.g., "+200 kcal - 50")
    nonisolated static func netCalorieAdjustment(from text: String) -> Double? {
        let lowered = text.lowercased()
        let unitPattern = #"\b(?:kcal|cal|calorie|calories)\b"#
        guard lowered.range(of: unitPattern, options: .regularExpression) != nil else {
            return nil
        }
        
        let tokenPattern = #"([+-]?)\s*(\d+(?:\.\d+)?)\s*(?:kcal|cal|calorie|calories)?"#
        guard let regex = try? NSRegularExpression(pattern: tokenPattern, options: .caseInsensitive) else {
            return nil
        }
        
        let ns = lowered as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: lowered, options: [], range: fullRange)
        guard !matches.isEmpty else { return nil }
        
        var total: Double = 0
        
        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let signRange = match.range(at: 1)
            let amountRange = match.range(at: 2)
            guard amountRange.location != NSNotFound else { continue }
            
            let signToken = signRange.location != NSNotFound ? ns.substring(with: signRange) : ""
            let normalizedAmount = ns.substring(with: amountRange).replacingOccurrences(of: ",", with: ".")
            guard let amount = Double(normalizedAmount) else { continue }
            let multiplier = signToken.contains("-") ? -1.0 : 1.0
            total += multiplier * amount
        }
        
        let remainder = regex.stringByReplacingMatches(in: lowered, options: [], range: fullRange, withTemplate: " ")
        if remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return total
        }
        return nil
    }
    
    // Detect currency-only adjustment expressions (e.g., "+200 try - 100 try")
    nonisolated static func netCurrencyAdjustment(from text: String) -> (net: Double, currency: String)? {
        let lowered = text.lowercased()
        let tokenPattern = #"([+-]?)\s*(\d+(?:\.\d+)?)\s*([a-z]{3}|usd|eur|try|gbp|tl|\$|€|₺|£)"#
        guard let regex = try? NSRegularExpression(pattern: tokenPattern, options: .caseInsensitive) else {
            return nil
        }
        
        let ns = lowered as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: lowered, options: [], range: fullRange)
        guard !matches.isEmpty else { return nil }
        
        var components: [(amount: Double, currency: String)] = []
        
        for match in matches {
            guard match.numberOfRanges >= 4 else { continue }
            let signRange = match.range(at: 1)
            let amountRange = match.range(at: 2)
            let currencyRange = match.range(at: 3)
            guard amountRange.location != NSNotFound, currencyRange.location != NSNotFound else { continue }
            
            let signToken = signRange.location != NSNotFound ? ns.substring(with: signRange) : ""
            let amountToken = ns.substring(with: amountRange).replacingOccurrences(of: ",", with: ".")
            let currencyToken = ns.substring(with: currencyRange)
            
            guard let amount = Double(amountToken),
                  let currency = normalizeCurrencyCode(currencyToken) else { continue }
            
            let multiplier = signToken.contains("-") ? -1.0 : 1.0
            components.append((amount: multiplier * amount, currency: currency))
        }
        
        guard !components.isEmpty else { return nil }
        guard let firstCurrency = components.first?.currency,
              components.allSatisfy({ $0.currency == firstCurrency }) else {
            return nil
        }
        
        let remainder = regex.stringByReplacingMatches(in: lowered, options: [], range: fullRange, withTemplate: " ")
        if remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let net = components.reduce(0) { $0 + $1.amount }
            return (net: net, currency: firstCurrency)
        }
        return nil
    }
    
    private static func normalizeCurrencyCode(_ token: String) -> String? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let upper = trimmed.uppercased()
        
        switch upper {
        case "$":
            return "USD"
        case "€":
            return "EUR"
        case "£":
            return "GBP"
        case "₺", "TL", "YTL":
            return "TRY"
        default:
            if upper == "USD" || upper == "US$" {
                return "USD"
            }
            if upper == "EUR" {
                return "EUR"
            }
            if upper == "TRY" {
                return "TRY"
            }
            if upper == "GBP" {
                return "GBP"
            }
            if upper.count == 3, upper.allSatisfy({ $0.isLetter }) {
                return upper
            }
            return nil
        }
    }
}

// MARK: - Unit Conversion Helpers

nonisolated struct UnitConversionHelper {
    // MARK: - Weight Conversions
    
    // Convert kg to lbs
    nonisolated static func kilogramsToPounds(_ kg: Double) -> Double {
        return kg * 2.20462
    }
    
    // Convert lbs to kg
    nonisolated static func poundsToKilograms(_ lbs: Double) -> Double {
        return lbs / 2.20462
    }
    
    // MARK: - Height Conversions
    
    // Convert cm to feet and inches
    nonisolated static func centimetersToFeetInches(_ cm: Double) -> (feet: Int, inches: Double) {
        let totalInches = cm / 2.54
        let feet = Int(totalInches / 12)
        let inches = totalInches.truncatingRemainder(dividingBy: 12)
        return (feet, inches)
    }
    
    // Convert feet and inches to cm
    nonisolated static func feetInchesToCentimeters(feet: Int, inches: Double) -> Double {
        let totalInches = Double(feet) * 12 + inches
        return totalInches * 2.54
    }
    
    // MARK: - Distance Conversions
    
    // Convert km to miles
    nonisolated static func kilometersToMiles(_ km: Double) -> Double {
        return km * 0.621371
    }
    
    // Convert miles to km
    nonisolated static func milesToKilometers(_ miles: Double) -> Double {
        return miles / 0.621371
    }
    
    // MARK: - Locale-based Formatting
    
    // Format weight for display based on locale
    nonisolated static func formatWeight(_ kg: Double, unitSystem: UnitSystem? = nil) -> String {
        let system = unitSystem ?? (UserDefaults.standard.string(forKey: "unitSystem").flatMap(UnitSystem.init) ?? .metric)
        
        if system == .metric {
            return String(format: "%.1f kg", kg)
        } else {
            let lbs = kilogramsToPounds(kg)
            return String(format: "%.1f lbs", lbs)
        }
    }
    
    // Format height for display based on locale
    nonisolated static func formatHeight(_ cm: Double, unitSystem: UnitSystem? = nil) -> String {
        let system = unitSystem ?? (UserDefaults.standard.string(forKey: "unitSystem").flatMap(UnitSystem.init) ?? .metric)
        
        if system == .metric {
            return String(format: "%.1f cm", cm)
        } else {
            let (feet, inches) = centimetersToFeetInches(cm)
            return String(format: "%d' %.1f\"", feet, inches)
        }
    }
    
    // Format distance for display based on locale
    nonisolated static func formatDistance(_ km: Double, unitSystem: UnitSystem? = nil) -> String {
        let system = unitSystem ?? (UserDefaults.standard.string(forKey: "unitSystem").flatMap(UnitSystem.init) ?? .metric)
        
        if system == .metric {
            return String(format: "%.2f km", km)
        } else {
            let miles = kilometersToMiles(km)
            return String(format: "%.2f miles", miles)
        }
    }
    
    // Parse weight from text (supports kg, lbs, pounds)
    nonisolated static func parseWeight(from text: String) -> (value: Double, unit: String)? {
        let lowered = text.lowercased()
        
        // Pattern: number + unit (kg, lbs, pounds, etc.)
        let pattern = #"(\d+(?:\.\d+)?)\s*(kg|kilogram|kilograms|lbs|lb|pound|pounds)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let ns = lowered as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: lowered, options: [], range: range),
              match.numberOfRanges >= 3 else {
            return nil
        }
        
        let valueRange = match.range(at: 1)
        let unitRange = match.range(at: 2)
        
        guard valueRange.location != NSNotFound,
              unitRange.location != NSNotFound else {
            return nil
        }
        
        let valueStr = ns.substring(with: valueRange)
        let unitStr = ns.substring(with: unitRange)
        
        guard let value = Double(valueStr) else {
            return nil
        }
        
        // Convert to kg
        let kg: Double
        if unitStr.contains("lb") || unitStr.contains("pound") {
            kg = poundsToKilograms(value)
        } else {
            kg = value
        }
        
        return (kg, "kg")
    }
    
    // Parse height from text (supports cm, m, feet, inches)
    nonisolated static func parseHeight(from text: String) -> (value: Double, unit: String)? {
        let lowered = text.lowercased()
        
        // Pattern 1: feet and inches (e.g., "5'10\"", "5 feet 10 inches")
        let feetInchesPattern = #"(\d+)\s*(?:'|feet|ft)\s*(?:(\d+(?:\.\d+)?)\s*(?:"|inches|in))?"#
        if let regex = try? NSRegularExpression(pattern: feetInchesPattern, options: .caseInsensitive) {
            let ns = lowered as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: lowered, options: [], range: range),
               match.numberOfRanges >= 2 {
                let feetRange = match.range(at: 1)
                if feetRange.location != NSNotFound,
                   let feet = Int(ns.substring(with: feetRange)) {
                    var inches: Double = 0
                    if match.numberOfRanges >= 3 {
                        let inchesRange = match.range(at: 2)
                        if inchesRange.location != NSNotFound {
                            inches = Double(ns.substring(with: inchesRange)) ?? 0
                        }
                    }
                    let cm = feetInchesToCentimeters(feet: feet, inches: inches)
                    return (cm, "cm")
                }
                // If feet parsing failed, try next pattern
            }
        }
        
        // Pattern 2: cm or meters (e.g., "175 cm", "1.75 m")
        let metricPattern = #"(\d+(?:\.\d+)?)\s*(cm|centimeter|centimeters|meter|meters|m)"#
        if let regex = try? NSRegularExpression(pattern: metricPattern, options: .caseInsensitive) {
            let ns = lowered as NSString
            let range = NSRange(location: 0, length: ns.length)
            if let match = regex.firstMatch(in: lowered, options: [], range: range),
               match.numberOfRanges >= 3 {
                let valueRange = match.range(at: 1)
                let unitRange = match.range(at: 2)
                
                guard valueRange.location != NSNotFound,
                      unitRange.location != NSNotFound,
                      let value = Double(ns.substring(with: valueRange)) else {
                    return nil
                }
                
                let unitStr = ns.substring(with: unitRange)
                let cm: Double
                if unitStr.contains("m") && !unitStr.contains("cm") {
                    // meters to cm
                    cm = value * 100
                } else {
                    cm = value
                }
                
                return (cm, "cm")
            }
        }
        
        return nil
    }
    
    // Parse distance from text (supports km, miles)
    nonisolated static func parseDistance(from text: String) -> (value: Double, unit: String)? {
        let lowered = text.lowercased()
        
        // Pattern: number + unit (km, miles, etc.)
        let pattern = #"(\d+(?:\.\d+)?)\s*(km|kilometer|kilometers|mile|miles|mi)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        
        let ns = lowered as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: lowered, options: [], range: range),
              match.numberOfRanges >= 3 else {
            return nil
        }
        
        let valueRange = match.range(at: 1)
        let unitRange = match.range(at: 2)
        
        guard valueRange.location != NSNotFound,
              unitRange.location != NSNotFound,
              let value = Double(ns.substring(with: valueRange)) else {
            return nil
        }
        
        let unitStr = ns.substring(with: unitRange)
        
        // Convert to km
        let km: Double
        if unitStr.contains("mile") || unitStr.contains("mi") {
            km = milesToKilometers(value)
        } else {
            km = value
        }
        
        return (km, "km")
    }
    
    // MARK: - Activity Calorie Calculation
    
    // Calculate calories burned for running/walking based on distance (km) and weight (kg)
    // Formula: Calories = distance_km * weight_kg * MET_value
    // MET values: Running ~10, Walking ~3.5, Cycling ~6
    nonisolated static func calculateActivityCalories(
        distanceKm: Double?,
        durationHours: Double?,
        activityType: String?,
        weightKg: Double?
    ) -> Double? {
        guard let weight = weightKg, weight > 0 else {
            return nil
        }
        
        // Determine Energy Coefficient (kcal/kg/km)
        // Approximate values from literature
        let coefficient: Double
        let met: Double
        
        if let activity = activityType?.lowercased() {
             if activity.contains("run") || activity.contains("jog") || activity.contains("koşu") {
                coefficient = 1.03
                met = 10.0
             } else if activity.contains("walk") || activity.contains("yürüyüş") {
                coefficient = 0.5
                met = 3.5
             } else if activity.contains("cycl") || activity.contains("bike") || activity.contains("bisiklet") {
                coefficient = 0.35
                met = 7.0
             } else {
                coefficient = 0.8
                met = 5.0
             }
        } else {
            coefficient = 0.8
            met = 5.0
        }
        
        // Prefer distance-based calculation (more accurate)
        if let distance = distanceKm, distance > 0 {
            // Calories = distance_km * weight_kg * coefficient
            return distance * weight * coefficient
        }
        
        // Fallback to duration-based if distance not available
        if let duration = durationHours, duration > 0 {
            // Calories per hour = weight_kg * MET
            // Total calories = calories_per_hour * duration_hours
            return weight * met * duration
        }
        
        return nil
    }
}
