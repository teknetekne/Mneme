import Foundation

struct NotepadFormatter {
    static func formatIntentForDisplay(_ intent: String) -> String {
        switch intent.lowercased() {
        case "reminder": return "Reminder"
        case "event": return "Event"
        case "expense": return "Expense"
        case "income": return "Income"
        case "activity": return "Activity"
        case "meal": return "Meal"
        case "work_start": return "Work Start"
        case "work_end": return "Work End"
        case "journal": return "Journal"
        default: return intent.capitalized
        }
    }
    
    static func formatTimeForDisplay(_ timeString: String) -> String {
        let components = timeString.split(separator: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else {
            return ""
        }
        
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        DateHelper.applyTimeFormat(formatter)
        
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        if let date = formatter.calendar.date(from: dateComponents) {
            return formatter.string(from: date)
        }
        
        return String(format: "%02d:%02d", hour, minute)
    }
    
    static func formatDayForDisplay(_ dayLabel: String) -> String {
        let locale = Locale.current
        var calendar = Calendar.current
        calendar.locale = locale
        
        // Localize absolute dates
        if let absoluteDate = DateHelper.absoluteDate(from: dayLabel) {
            let formatter = DateFormatter()
            formatter.locale = locale  // Use user's language
            formatter.calendar = calendar
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: absoluteDate)
        }
        
        // Localize relative dates
        let languageCode = locale.language.languageCode?.identifier ?? "en"
        
        switch languageCode {
        case "tr":  // Turkish
            switch dayLabel.lowercased() {
            case "today": return "bugün"
            case "tomorrow": return "yarın"
            case "next_monday": return "gelecek pazartesi"
            case "next_tuesday": return "gelecek salı"
            case "next_wednesday": return "gelecek çarşamba"
            case "next_thursday": return "gelecek perşembe"
            case "next_friday": return "gelecek cuma"
            case "next_saturday": return "gelecek cumartesi"
            case "next_sunday": return "gelecek pazar"
            case "weekday_monday": return "pazartesi"
            case "weekday_tuesday": return "salı"
            case "weekday_wednesday": return "çarşamba"
            case "weekday_thursday": return "perşembe"
            case "weekday_friday": return "cuma"
            case "weekday_saturday": return "cumartesi"
            case "weekday_sunday": return "pazar"
            default: return dayLabel
            }
        case "en":  // English (default)
            switch dayLabel.lowercased() {
            case "today": return "today"
            case "tomorrow": return "tomorrow"
            case "next_monday": return "next Monday"
            case "next_tuesday": return "next Tuesday"
            case "next_wednesday": return "next Wednesday"
            case "next_thursday": return "next Thursday"
            case "next_friday": return "next Friday"
            case "next_saturday": return "next Saturday"
            case "next_sunday": return "next Sunday"
            case "weekday_monday": return "Monday"
            case "weekday_tuesday": return "Tuesday"
            case "weekday_wednesday": return "Wednesday"
            case "weekday_thursday": return "Thursday"
            case "weekday_friday": return "Friday"
            case "weekday_saturday": return "Saturday"
            case "weekday_sunday": return "Sunday"
            default: return dayLabel  // Return absolute dates as-is
            }
        default:  // Use DateFormatter for other languages
            return formatDayWithFormatter(dayLabel, locale: locale)
        }
    }
    
    private static func formatDayWithFormatter(_ dayLabel: String, locale: Locale) -> String {
        // Try to convert relative dates using DateFormatter
        // Return original value if unsuccessful
        let formatter = DateFormatter()
        formatter.locale = locale
        
        // Simple translation table
        let translations: [String: String] = [
            "today": NSLocalizedString("today", comment: ""),
            "tomorrow": NSLocalizedString("tomorrow", comment: "")
        ]
        
        let lowercased = dayLabel.lowercased()
        if let translated = translations[lowercased] {
            return translated
        }
        
        // Return English for other relative dates
        switch lowercased {
        case "next_monday": return "next Monday"
        case "next_tuesday": return "next Tuesday"
        case "next_wednesday": return "next Wednesday"
        case "next_thursday": return "next Thursday"
        case "next_friday": return "next Friday"
        case "next_saturday": return "next Saturday"
        case "next_sunday": return "next Sunday"
        case "weekday_monday": return "Monday"
        case "weekday_tuesday": return "Tuesday"
        case "weekday_wednesday": return "Wednesday"
        case "weekday_thursday": return "Thursday"
        case "weekday_friday": return "Friday"
        case "weekday_saturday": return "Saturday"
        case "weekday_sunday": return "Sunday"
        default: return dayLabel
        }
    }
    
    static func formatDayForDisplayEnglish(_ dayLabel: String) -> String {
        if let absoluteDate = DateHelper.absoluteDate(from: dayLabel) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: absoluteDate)
        }

        switch dayLabel.lowercased() {
        case "today": return "today"
        case "tomorrow": return "tomorrow"
        case "next_monday": return "next Monday"
        case "next_tuesday": return "next Tuesday"
        case "next_wednesday": return "next Wednesday"
        case "next_thursday": return "next Thursday"
        case "next_friday": return "next Friday"
        case "next_saturday": return "next Saturday"
        case "next_sunday": return "next Sunday"
        case "weekday_monday": return "Monday"
        case "weekday_tuesday": return "Tuesday"
        case "weekday_wednesday": return "Wednesday"
        case "weekday_thursday": return "Thursday"
        case "weekday_friday": return "Friday"
        case "weekday_saturday": return "Saturday"
        case "weekday_sunday": return "Sunday"
        default: return dayLabel
        }
    }
    
    static func normalizeIntentForCheck(_ displayIntent: String) -> String {
        switch displayIntent.lowercased() {
        case "reminder": return "reminder"
        case "event": return "event"
        case "expense": return "expense"
        case "income": return "income"
        case "activity": return "activity"
        case "meal": return "meal"
        case "work start": return "work_start"
        case "work end": return "work_end"
        default: return displayIntent.lowercased().replacingOccurrences(of: " ", with: "_")
        }
    }
}
