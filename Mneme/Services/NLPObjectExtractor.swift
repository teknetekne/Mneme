import Foundation

nonisolated struct NLPObjectExtractor {
    nonisolated static func extract(originalText: String, fallback: String?, parsedDay: String?, parsedTime: String?) -> String {
        var working = originalText
        working = removeURLsAndHandles(from: working)
        working = NLPDateTimeSanitizer.stripDateTimeFragments(from: working)
        working = remove(dayLabel: parsedDay, from: working)
        working = remove(timeLabel: parsedTime, from: working)
        working = stripCommandPrefixes(from: working)
        working = stripTrailingCourtesy(from: working)
        working = removeResidualPunctuation(from: working)
        working = condenseWhitespace(in: working)
        let normalized = slugify(working)
        if !normalized.isEmpty {
            return normalized
        }
        if let fallback = fallback, !fallback.isEmpty {
            let fallbackSlug = slugify(fallback)
            if !fallbackSlug.isEmpty {
                return fallbackSlug
            }
        }
        return slugify(originalText)
    }
}

nonisolated private extension NLPObjectExtractor {
    nonisolated static func removeURLsAndHandles(from text: String) -> String {
        var cleaned = text
        let patterns = [
            "https?://[^\\s]+",
            "www\\.[^\\s]+",
            "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",
            "@[^\\s]+",
            "#[\\p{L}0-9_]+"
        ]
        for pattern in patterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        return cleaned
    }
    
    nonisolated static func remove(dayLabel: String?, from text: String) -> String {
        guard let dayLabel, !dayLabel.isEmpty else { return text }
        var cleaned = text
        let escaped = NSRegularExpression.escapedPattern(for: dayLabel)
        cleaned = cleaned.replacingOccurrences(of: "(?i)\\b" + escaped + "\\b", with: " ", options: .regularExpression)
        // Skip DateHelper.absoluteDate call (main actor isolated)
        return cleaned
    }
    
    static func remove(timeLabel: String?, from text: String) -> String {
        guard let timeLabel, !timeLabel.isEmpty else { return text }
        var cleaned = text
        for variant in timeVariants(for: timeLabel) {
            let escaped = NSRegularExpression.escapedPattern(for: variant)
            cleaned = cleaned.replacingOccurrences(of: "(?i)\\b" + escaped + "\\b", with: " ", options: .regularExpression)
        }
        return cleaned
    }
    
    static func stripCommandPrefixes(from text: String) -> String {
        var mutable = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = true
        while changed && !mutable.isEmpty {
            changed = false
            for phrase in commandPrefixes {
                if let range = mutable.range(of: phrase, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) {
                    mutable.removeSubrange(range)
                    mutable = mutable.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-–—,;")))
                    changed = true
                    break
                }
            }
        }
        return mutable
    }
    
    static func stripTrailingCourtesy(from text: String) -> String {
        var cleaned = text
        cleaned = cleaned.replacingOccurrences(of: trailingCourtesyPattern, with: "", options: [.regularExpression, .caseInsensitive])
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    static func removeResidualPunctuation(from text: String) -> String {
        var cleaned = text
        cleaned = cleaned.replacingOccurrences(of: "[\\[\\]{}()]+", with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "[\"\"\"\"«»‚'']+", with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "[,.;!?]+", with: " ", options: .regularExpression)
        return cleaned
    }
    
    static func condenseWhitespace(in text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    static func slugify(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        var components: [String] = []
        var current = ""
        for scalar in trimmed.lowercased() {
            if scalar.isLetter || scalar.isNumber {
                current.append(scalar)
            } else {
                if !current.isEmpty {
                    components.append(current)
                    current = ""
                }
            }
        }
        if !current.isEmpty {
            components.append(current)
        }
        let slug = components.filter { !$0.isEmpty }.joined(separator: "_")
        return slug.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
    
    static func dateVariants(for date: Date) -> Set<String> {
        var variants: Set<String> = []
        let locales: [Locale] = [.current, Locale(identifier: "en_US_POSIX"), Locale(identifier: "tr_TR")]
        let formats = [
            "d MMMM", "d MMM", "MMMM d", "MMM d",
            "dd.MM.yyyy", "dd.MM", "d.M.",
            "dd/MM/yyyy", "dd/MM", "d/M/yy",
            "MM/dd/yyyy", "MM/dd", "M/d/yy"
        ]
        let calendar = Calendar(identifier: .gregorian)
        for locale in locales {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = locale
            for format in formats {
                formatter.dateFormat = format
                variants.insert(formatter.string(from: date))
            }
        }
        return variants
    }
    
    static func timeVariants(for time: String) -> Set<String> {
        let parts = time.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
            return [time]
        }
        let hourNoPad = String(hour)
        let hourPad = String(format: "%02d", hour)
        let minutePad = String(format: "%02d", minute)
        let colon = hourPad + ":" + minutePad
        let colonNoPad = hourNoPad + ":" + minutePad
        let dot = hourPad + "." + minutePad
        let dotNoPad = hourNoPad + "." + minutePad
        return [time, colon, colonNoPad, dot, dotNoPad, hourPad, hourNoPad]
    }
}

nonisolated private let commandPrefixes: [String] = [
    "remind me to",
    "remind me",
    "please remind me to",
    "please remind me",
    "remember to",
    "remember that",
    "set a reminder for",
    "create a reminder for",
    "create reminder for",
    "add reminder for",
    "create an event for",
    "create event for",
    "schedule an event for",
    "schedule",
    "note to",
    "bana hatırlat",
    "beni hatırlat",
    "hatırlat bana",
    "lütfen hatırlat",
    "hatırlat",
    "hatirlat",
    "recuérdame",
    "recuerdame",
    "recordarme",
    "ponme un recordatorio",
    "crea un recordatorio",
    "créame un evento",
    "agrega un recordatorio",
    "agendar",
    "agenda",
    "lembra-me de",
    "lembre-me de",
    "me lembra de",
    "adiciona um lembrete",
    "cria um evento",
    "erinnere mich",
    "bitte erinnere mich",
    "termin erstellen",
    "rappelle-moi",
    "rappelle moi",
    "crée un rappel",
    "planifie",
    "ricordami",
    "imposta un promemoria",
    "crea un evento"
]

nonisolated private let trailingCourtesyPattern = "(?i)(?:[,\\u{2009}\\s]*(?:please|thanks|teşekkürler|lütfen|por favor|gracias|merci|danke|obrigado|grazie))+$"
