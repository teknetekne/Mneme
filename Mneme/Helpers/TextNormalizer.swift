import Foundation

nonisolated enum TextNormalizer {
    nonisolated static func normalize(_ text: String) -> String {
        var result = text
        result = normalizeRelativeTime(result)
        result = normalizeHalfPast(result)
        result = normalizeQuarterPastTo(result)
        result = normalizeAMPM(result)
        return result
    }
    
    private nonisolated static func normalizeRelativeTime(_ text: String) -> String {
        // Examples: "in two hours" -> "14:30" (if current time is 12:30)
        let pattern = #"\bin\s+(\d+)\s+(?:hour|hours|hr|hrs)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        
        let calendar = Calendar.current
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        
        let ns = text as NSString
        var output = text
        var offset = 0
        
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let hoursRange = match.range(at: 1)
            guard hoursRange.location != NSNotFound else { continue }
            
            let hoursToAdd = Int(ns.substring(with: hoursRange)) ?? 0
            let targetHour = (currentHour + hoursToAdd) % 24
            let replacement = String(format: "%02d:%02d", targetHour, currentMinute)
            
            let fullRange = match.range(at: 0)
            if let r = Range(NSRange(location: fullRange.location + offset, length: fullRange.length), in: output) {
                output.replaceSubrange(r, with: replacement)
                offset += replacement.count - fullRange.length
            }
        }
        return output
    }
    
    private nonisolated static func normalizeHalfPast(_ text: String) -> String {
        // Examples: "half past eight" -> "20:30" or "08:30" (context-dependent)
        // "half past 8" -> "20:30" or "08:30"
        // Try to detect AM/PM context from surrounding text
        let pattern = #"\bhalf\s+past\s+(1[0-2]|0?[1-9])\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        
        let ns = text as NSString
        var output = text
        var offset = 0
        
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let hourRange = match.range(at: 1)
            guard hourRange.location != NSNotFound else { continue }
            
            let hour = Int(ns.substring(with: hourRange)) ?? 0
            guard hour >= 1 && hour <= 12 else { continue }
            
            // Check for AM/PM context after the match
            let afterMatch = match.range(at: 0).location + match.range(at: 0).length
            let remainingText = afterMatch < ns.length ? ns.substring(from: afterMatch).lowercased() : ""
            let hasAM = remainingText.contains(" am") || remainingText.prefix(10).contains("am")
            let hasPM = remainingText.contains(" pm") || remainingText.prefix(10).contains("pm")
            
            // Default to PM for evening hours (6-11), AM for morning (1-5, 12)
            let isPM = hasPM || (!hasAM && (hour >= 6 && hour <= 11))
            let h24 = isPM ? (hour == 12 ? 12 : hour + 12) : (hour == 12 ? 0 : hour)
            
            let replacement = String(format: "%02d:30", h24)
            
            let fullRange = match.range(at: 0)
            if let r = Range(NSRange(location: fullRange.location + offset, length: fullRange.length), in: output) {
                output.replaceSubrange(r, with: replacement)
                offset += replacement.count - fullRange.length
            }
        }
        return output
    }
    
    private nonisolated static func normalizeQuarterPastTo(_ text: String) -> String {
        // Examples: "quarter past eight" -> "20:15" or "08:15"
        // "quarter to nine" -> "20:45" or "08:45"
        let quarterPastPattern = #"\bquarter\s+past\s+(1[0-2]|0?[1-9])\b"#
        let quarterToPattern = #"\bquarter\s+to\s+(1[0-2]|0?[1-9])\b"#
        
        var output = text
        
        // Quarter past
        if let regex = try? NSRegularExpression(pattern: quarterPastPattern, options: .caseInsensitive) {
            let ns = output as NSString
            var offset = 0
            
            for match in regex.matches(in: output, range: NSRange(location: 0, length: ns.length)).reversed() {
                let hourRange = match.range(at: 1)
                guard hourRange.location != NSNotFound else { continue }
                
                let hour = Int(ns.substring(with: hourRange)) ?? 0
                guard hour >= 1 && hour <= 12 else { continue }
                
                // Check for AM/PM context
                let afterMatch = match.range(at: 0).location + match.range(at: 0).length
                let remainingText = afterMatch < ns.length ? ns.substring(from: afterMatch).lowercased() : ""
                let hasAM = remainingText.contains(" am") || remainingText.prefix(10).contains("am")
                let hasPM = remainingText.contains(" pm") || remainingText.prefix(10).contains("pm")
                
                let isPM = hasPM || (!hasAM && (hour >= 6 && hour <= 11))
                let h24 = isPM ? (hour == 12 ? 12 : hour + 12) : (hour == 12 ? 0 : hour)
                
                let replacement = String(format: "%02d:15", h24)
                
                let fullRange = match.range(at: 0)
                if let r = Range(NSRange(location: fullRange.location + offset, length: fullRange.length), in: output) {
                    output.replaceSubrange(r, with: replacement)
                    offset += replacement.count - fullRange.length
                }
            }
        }
        
        // Quarter to
        if let regex = try? NSRegularExpression(pattern: quarterToPattern, options: .caseInsensitive) {
            let ns = output as NSString
            var offset = 0
            
            for match in regex.matches(in: output, range: NSRange(location: 0, length: ns.length)).reversed() {
                let hourRange = match.range(at: 1)
                guard hourRange.location != NSNotFound else { continue }
                
                let hour = Int(ns.substring(with: hourRange)) ?? 0
                guard hour >= 1 && hour <= 12 else { continue }
                
                // Quarter to means 15 minutes before the hour
                let targetHour = hour == 1 ? 12 : hour - 1
                
                // Check for AM/PM context
                let afterMatch = match.range(at: 0).location + match.range(at: 0).length
                let remainingText = afterMatch < ns.length ? ns.substring(from: afterMatch).lowercased() : ""
                let hasAM = remainingText.contains(" am") || remainingText.prefix(10).contains("am")
                let hasPM = remainingText.contains(" pm") || remainingText.prefix(10).contains("pm")
                
                let isPM = hasPM || (!hasAM && (targetHour >= 6 && targetHour <= 11))
                let h24 = isPM ? (targetHour == 12 ? 12 : targetHour + 12) : (targetHour == 12 ? 0 : targetHour)
                
                let replacement = String(format: "%02d:45", h24)
                
                let fullRange = match.range(at: 0)
                if let r = Range(NSRange(location: fullRange.location + offset, length: fullRange.length), in: output) {
                    output.replaceSubrange(r, with: replacement)
                    offset += replacement.count - fullRange.length
                }
            }
        }
        
        return output
    }

    private nonisolated static func normalizeAMPM(_ text: String) -> String {
        // Examples: 5pm -> 17:00, 12am -> 00:00, 12pm -> 12:00, 7:30pm -> 19:30
        let pattern = "\\b(1[0-2]|0?[1-9])(?::([0-5][0-9]))?\\s*([AaPp][Mm])\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var output = text
        var offset = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let hourRange = match.range(at: 1)
            let minuteRange = match.range(at: 2)
            let meridiemRange = match.range(at: 3)

            let hour = Int(ns.substring(with: hourRange)) ?? 0
            let minutes = minuteRange.location != NSNotFound ? ns.substring(with: minuteRange) : "00"
            let meridiem = ns.substring(with: meridiemRange).lowercased()

            var h24 = hour % 12
            if meridiem == "pm" { h24 += 12 }
            let hh = String(format: "%02d", h24)
            let mm = String(format: "%02d", Int(minutes) ?? 0)
            let replacement = "\(hh):\(mm)"

            let fullRange = match.range(at: 0)
            if let r = Range(NSRange(location: fullRange.location + offset, length: fullRange.length), in: output) {
                output.replaceSubrange(r, with: replacement)
                offset += replacement.count - fullRange.length
            }
        }
        return output
    }
}




