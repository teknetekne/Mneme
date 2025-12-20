import Foundation

struct NotepadSummaryBuilder {
    static func buildSummaryText(from results: [ParsingResultItem], originalText: String) -> String? {
        guard !results.isEmpty else {
            return nil
        }
        
        let intentItem = results.first { $0.field == "Intent" }
        guard let intent = intentItem else {
            return nil
        }
        
        var parts: [String] = []
        let normalizedIntent = NotepadFormatter.normalizeIntentForCheck(intent.value)
        
        if normalizedIntent == "work_start" || normalizedIntent.contains("work_start") {
            var timeToShow: String? = nil
            if let timeItem = results.first(where: { ($0.field == "Event Time" || $0.field == "Reminder Time") && $0.isValid }) {
                // timeItem.value already formatted by formatTimeForDisplay in NotepadViewModel
                timeToShow = timeItem.value
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone.current
                let currentTime = formatter.string(from: Date())
                let displayTime = NotepadFormatter.formatTimeForDisplay(currentTime)
                timeToShow = displayTime.isEmpty ? currentTime : displayTime
            }
            if let time = timeToShow {
                parts.append("\(originalText) - \(time)")
            } else {
                parts.append(originalText)
            }
            return parts.joined(separator: " ")
        }
        
        if normalizedIntent == "work_end" || normalizedIntent.contains("work_end") {
            var timeToShow: String? = nil
            if let timeItem = results.first(where: { ($0.field == "Event Time" || $0.field == "Reminder Time") && $0.isValid }) {
                // timeItem.value already formatted by formatTimeForDisplay in NotepadViewModel
                timeToShow = timeItem.value
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone.current
                let currentTime = formatter.string(from: Date())
                let displayTime = NotepadFormatter.formatTimeForDisplay(currentTime)
                timeToShow = displayTime.isEmpty ? currentTime : displayTime
            }
            if let time = timeToShow {
                parts.append("\(originalText) - \(time)")
            } else {
                parts.append(originalText)
            }
            return parts.joined(separator: " ")
        }
        
        switch normalizedIntent {
        case "income":
            if let amountItem = results.first(where: { $0.field == "Amount" && $0.isValid }) {
                // Extract amount value (remove currency symbols and signs)
                let amountValue = amountItem.value
                    .replacingOccurrences(of: "+", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .trimmingCharacters(in: .whitespaces)
                parts.append("+ \(amountValue)")
            } else {
                return nil
            }
            
        case "expense":
            if let amountItem = results.first(where: { $0.field == "Amount" && $0.isValid }) {
                // Extract amount value (remove currency symbols and signs)
                let amountValue = amountItem.value
                    .replacingOccurrences(of: "+", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .trimmingCharacters(in: .whitespaces)
                parts.append("- \(amountValue)")
            } else {
                return nil
            }
            
        case "meal":
            // Check if we have multiple meal objects
            if let subjectItem = results.first(where: { $0.field == "Subject" && !$0.value.isEmpty }),
               subjectItem.value.contains(" + ") {
                // Multiple meal objects - format as "Pizza x kcal, Apple x kcal"
                let mealObjects = subjectItem.value.components(separatedBy: " + ")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                
                var mealParts: [String] = []
                for mealName in mealObjects {
                    // Look for individual Calories field for this meal (field name is "Calories - {CapitalizedMealName}")
                    let caloriesFieldName = "Calories - \(mealName)"
                    if let caloriesItem = results.first(where: { $0.field == caloriesFieldName }) {
                        if caloriesItem.isValid && caloriesItem.value != "Not found" {
                            mealParts.append("\(mealName) \(caloriesItem.value)")
                        } else {
                            // Show meal name even if calories not found
                            mealParts.append(mealName)
                        }
                    } else {
                        // Fallback: just show meal name
                        mealParts.append(mealName)
                    }
                }
                
                if !mealParts.isEmpty {
                    parts.append(mealParts.joined(separator: ", "))
                } else {
                    // Fallback to subject if no calories found
                    parts.append(subjectItem.value)
                }
            } else {
                // Single meal object
                if let subjectItem = results.first(where: { $0.field == "Subject" && !$0.value.isEmpty }),
                   let caloriesItem = results.first(where: { $0.field == "Calories" && $0.isValid }) {
                    parts.append("\(subjectItem.value) \(caloriesItem.value)")
                } else if let subjectItem = results.first(where: { $0.field == "Subject" && !$0.value.isEmpty }) {
                    parts.append(subjectItem.value)
                } else {
                    return nil
                }
            }
            
        case "reminder":
            if let timeItem = results.first(where: { $0.field == "Reminder Time" && $0.isValid }),
               let dayItem = results.first(where: { $0.field == "Reminder Day" && $0.isValid }) {
                // timeItem.value already formatted by formatTimeForDisplay in NotepadViewModel
                let time = timeItem.value
                let day = NotepadFormatter.formatDayForDisplayEnglish(dayItem.value)
                parts.append("Reminder will be created")
                if !day.isEmpty {
                    parts.append("on \(day)")
                }
                if !time.isEmpty {
                    parts.append("at \(time)")
                }
            } else {
                parts.append("Reminder will be created")
            }
            
        case "event":
            if let timeItem = results.first(where: { $0.field == "Event Time" && $0.isValid }),
               let dayItem = results.first(where: { $0.field == "Event Day" && $0.isValid }) {
                // timeItem.value already formatted by formatTimeForDisplay in NotepadViewModel
                let time = timeItem.value
                let day = NotepadFormatter.formatDayForDisplayEnglish(dayItem.value)
                parts.append("Event will be created")
                if !day.isEmpty {
                    parts.append("on \(day)")
                }
                if !time.isEmpty {
                    parts.append("at \(time)")
                }
            } else {
                parts.append("Event will be created")
            }
            
        default:
            return nil
        }
        
        // Add subject for reminder and event if not already included
        if normalizedIntent == "reminder" || normalizedIntent == "event" {
            if let objectItem = results.first(where: { $0.field == "Subject" && $0.isValid && !$0.value.isEmpty }) {
                parts.append("- \(objectItem.value)")
            }
        }
        
        return parts.joined(separator: " ")
    }
}
