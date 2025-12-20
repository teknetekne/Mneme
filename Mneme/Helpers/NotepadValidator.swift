import Foundation

struct NotepadValidator {
    static func isValidTime(_ timeString: String) -> Bool {
        // Current HH:mm check
        let components = timeString.split(separator: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else {
            // If not HH:mm format, perform natural language check
            return isValidNaturalTime(timeString)
        }
        return hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59
    }
    
    private static func isValidNaturalTime(_ timeString: String) -> Bool {
        // Try to parse using DateHelper
        // Accept as valid if successfully parseable
        return DateHelper.canParseTime(timeString)
    }
    
    static func isValidDate(_ dateString: String) -> Bool {
        // DateHelper.canParseDate ile kontrol et
        if DateHelper.canParseDate(dateString) {
            return true
        }
        
        // Check absolute dates (YYYY-MM-DD)
        if let _ = DateHelper.absoluteDate(from: dateString) {
            return true
        }
        
        // Check relative dates (today, tomorrow, next_monday)
        let validRelativeDates = [
            "today", "tomorrow",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
            "next_monday", "next_tuesday", "next_wednesday", "next_thursday", "next_friday", "next_saturday", "next_sunday",
            "weekday_monday", "weekday_tuesday", "weekday_wednesday", "weekday_thursday", "weekday_friday", "weekday_saturday", "weekday_sunday"
        ]
        
        return validRelativeDates.contains(dateString.lowercased())
    }
    
    static func isValidCurrency(_ currency: String) -> Bool {
        // Check ISO 4217 currency codes
        // Supported codes: USD, EUR, TRY, GBP, JPY, CNY, CAD, AUD
        // Case insensitive
        let validCurrencies = [
            "USD", "EUR", "TRY", "GBP", "JPY", "CNY", "CAD", "AUD"
        ]
        
        let upperCurrency = currency.uppercased()
        return validCurrencies.contains(upperCurrency)
    }
    
    static func isValidPositiveNumber(_ value: Double, min: Double = 0) -> Bool {
        // Check that value is positive and greater than minimum value
        return value > min
    }
    
    static func isValidAmount(_ amount: Double) -> Bool {
        // Check that amount is not zero
        // Can be negative/positive
        return amount != 0
    }
}





