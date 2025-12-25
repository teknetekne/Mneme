import Foundation

struct NLPSanitizedDateTime {
    let day: String?
    let time: String?
    let invalidDayInput: String?
    let invalidTimeInput: String?
}

nonisolated struct NLPDateTimeSanitizer {
    nonisolated static func sanitize(
        originalText: String,
        translatedText: String,
        candidateDay: String?,
        candidateTime: String?,
        calendar: Calendar = .current
    ) -> NLPSanitizedDateTime {
        let texts = [originalText, translatedText]
        
        // Only use explicitly detected day/time from text; ignore model candidate day/time unless text had tokens
        let dayDetection = detectDay(in: texts, candidate: nil, calendar: calendar)
        
        let period = detectPeriod(in: texts)
        let explicitTimeDetection = detectTime(in: texts, candidate: nil, period: period)
        let explicitTimeProvided = explicitTimeDetection.value != nil
        let timeDetection = explicitTimeDetection
        let relative = detectRelativeOffset(in: texts, calendar: calendar) ?? detectSimpleRelative(in: texts, calendar: calendar)
        var dayValue = dayDetection.value
        var timeValue = timeDetection.value
        var dayInvalid = dayDetection.invalidInput
        var timeInvalid = timeDetection.invalidInput
        if let relative = relative {
            let startOfDay = calendar.startOfDay(for: relative.date)
            let relativeDayString = DateHelper.absoluteDayString(from: startOfDay)
            switch relative.unit {
            case .minute, .hour:
                if let relativeDayString = relativeDayString {
                    dayValue = relativeDayString
                }
                let components = calendar.dateComponents([.hour, .minute], from: relative.date)
                if let hour = components.hour, let minute = components.minute {
                    timeValue = format(hour: hour, minute: minute)
                }
            case .day, .week, .month:
                if let relativeDayString = relativeDayString {
                    dayValue = relativeDayString
                }
                if !explicitTimeProvided {
                    timeValue = nil
                }
            }
        }
        
        // If there is a time but no day, default day to today
        if dayValue == nil, timeValue != nil {
            let today = calendar.startOfDay(for: Date())
            dayValue = DateHelper.absoluteDayString(from: today)
        }
        
        if dayValue != nil {
            dayInvalid = nil
        }
        if timeValue != nil {
            timeInvalid = nil
        }
        if let label = dayValue,
           let absolute = DateHelper.parseDate(dayLabel: label, timeString: nil) {
            dayValue = DateHelper.absoluteDayString(from: absolute)
        }
        return NLPSanitizedDateTime(
            day: dayValue,
            time: timeValue,
            invalidDayInput: dayInvalid,
            invalidTimeInput: timeInvalid
        )
    }
    
    nonisolated static func stripDateTimeFragments(from text: String) -> String {
        guard !text.isEmpty else { return text }
        var cleaned = text
        cleaned = replaceMatches(in: cleaned, regexes: dateTimeRegexes)
        
        let relativeRegexes: [NSRegularExpression] = [
            relativeDayRegex,
            timeKeywordRegex,
            relativeInAfterRegex,
            relativeLaterRegex,
            turkishRelativeRegex
        ].compactMap { $0 }
        
        cleaned = replaceMatches(in: cleaned, regexes: relativeRegexes)
        
        // Additional cleanup for common temporal suffixes or standalone words that might be missed
        let temporalSuffixes = ["'da", "'de", "'ta", "'te", "'yu", "'yi", "'u", "'i"]
        for suffix in temporalSuffixes {
            cleaned = cleaned.replacingOccurrences(of: suffix, with: " ", options: [.caseInsensitive])
        }
        
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Static caches
    
    private static let pmKeywords = [
        "aksam",
        "evening",
        "night",
        "gece",
        "soir",
        "abend",
        "tarde",
        "noite",
        "vespre",
        "afternoon",
        "ogleden",
        "ogleden sonra",
        "pm",
        "p.m"
    ]

    private static let amKeywords = [
        "sabah",
        "morning",
        "manha",
        "matin",
        "manana",
        "dawn",
        "am",
        "a.m"
    ]

    private static let noonKeywords = ["noon", "oglen", "midday", "mediodia"]
    private static let midnightKeywords = ["midnight", "gece_yarisi", "gece yarisi", "geceyarisi"]
    
    private static let nextWeekdayRegex = try! NSRegularExpression(
        pattern: "(?i)\\b(?:next(?:\\s+week)?|coming|haftaya)\\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun|pazartesi|sali|salı|carsamba|çarşamba|persembe|perşembe|cuma|cumartesi|pazar)\\b",
        options: [.useUnicodeWordBoundaries]
    )

    private static let numericDateRegex = try! NSRegularExpression(pattern: "(?<!\\d)(\\d{1,2})([./])(\\d{1,2})(?:[./](\\d{2,4}))?(?!\\d)")
    private static let colonTimeRegex = try! NSRegularExpression(pattern: "(?<!\\d)(\\d{1,2}):(\\d{2})(?!\\d)")
    private static let keywordTimeRegex = try! NSRegularExpression(pattern: "(?:(?:saat|hour|at|um|kl\\.?|klo|@)\\s*)(\\d{1,2})(?::(\\d{2}))?")
    private static let apostropheTimeRegex = try! NSRegularExpression(pattern: "(\\d{1,2})['’](?:de|da|te|ta)")
    private static let ampmRegex = try! NSRegularExpression(pattern: "(\\d{1,2})\\s*(a\\.?m\\.?|p\\.?m\\.?)")
    
    private static let timeKeywordRegex: NSRegularExpression? = {
        let tokens = [
            "saat","hour","hours","heure","hora","uhr","pm","am","p\\.?m\\.?","a\\.?m\\.?",
            "morning","afternoon","evening","night","noon","midnight",
            "sabah","öğlen","akşam","gece",
            "mañana","tarde","noche","mediodía","madrugada",
            "manhã","tarde","noite","meia\\s+noite",
            "matin","après-midi","soir","nuit","midi","minuit",
            "morgen","nachmittag","abend","nacht","mittag"
        ]
        let expanded = Array(Set(tokens.flatMap { token -> [String] in
            let folded = token.folding(options: [.diacriticInsensitive], locale: .current)
            if folded != token {
                return [token, folded]
            }
            return [token]
        }))
        let escaped = expanded.map { token -> String in
            if token.contains("\\s") { return token }
            return NSRegularExpression.escapedPattern(for: token)
        }
        let pattern = escaped.joined(separator: "|")
        return try? NSRegularExpression(pattern: "(?i)\\b(?:" + pattern + ")\\b", options: [.useUnicodeWordBoundaries])
    }()
    
    private static let periodPrefixedRegex: NSRegularExpression = {
        let keywords = (pmKeywords + amKeywords + noonKeywords + midnightKeywords)
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        return try! NSRegularExpression(pattern: "((?:" + keywords + "))\\s*(\\d{1,2})(?::(\\d{2}))?", options: [])
    }()
    
    private static var dateTimeRegexes: [NSRegularExpression] {
        return [
            colonTimeRegex,
            keywordTimeRegex,
            apostropheTimeRegex,
            ampmRegex,
            numericDateRegex,
            dayMonthRegex,
            monthDayRegex,
            periodPrefixedRegex,
            dayNameWithTimeRegex,
            dayNameRegex,
            nextWeekdayRegex
        ]
    }

    private static let relativeDayRegex: NSRegularExpression? = {
        let singleTokens = [
            "today","tomorrow","tonight","bugün","yarın","haftaya",
            "hoy","mañana","hoydia","hoje","amanhã",
            "aujourd'hui","demain",
            "heute","morgen",
            "oggi","domani"
        ].map { NSRegularExpression.escapedPattern(for: $0) }
        let phraseTokens = [
            "this\\s+evening","this\\s+morning","next\\s+week","next\\s+month",
            "bu\\s+akşam","bu\\s+sabah","esta\\s+noche","esta\\s+semana","próxima\\s+semana",
            "cette\\s+semaine","semaine\\s+prochaine",
            "diese\\s+woche","nächste\\s+woche",
            "questa\\s+settimana","prossima\\s+settimana"
        ]
        let pattern = (singleTokens + phraseTokens).joined(separator: "|")
        return try? NSRegularExpression(pattern: "(?i)\\b(?:" + pattern + ")\\b", options: [.useUnicodeWordBoundaries])
    }()

    private static let dayNameTokens: [String] = [
        "monday","tuesday","wednesday","thursday","friday","saturday","sunday",
        "mon","tue","wed","thu","fri","sat","sun",
        "pazartesi","salı","sali","çarşamba","carsamba","perşembe","persembe","cuma","cumartesi","pazar",
        "lunes","martes","miércoles","miercoles","jueves","viernes","sábado","sabado","domingo",
        "lundi","mardi","mercredi","jeudi","vendredi","samedi","dimanche",
        "montag","dienstag","mittwoch","donnerstag","freitag","samstag","sonntag",
        "oggi","domani","lunedi","martedi","mercoledi","giovedi","venerdi","sabato","domenica"
    ]

    private static let dayNamePattern: String = dayNameTokens
        .map { NSRegularExpression.escapedPattern(for: $0) }
        .joined(separator: "|")

    private static let dayNameRegex = try! NSRegularExpression(
        pattern: "(?i)\\b(?:" + dayNamePattern + ")\\b",
        options: [.useUnicodeWordBoundaries]
    )
    private static let dayNameWithTimeRegex = try! NSRegularExpression(
        pattern: "(?i)\\b(?:" + dayNamePattern + ")(?:\\s+at)?\\s+\\d{1,2}(?::\\d{2})?\\b",
        options: [.useUnicodeWordBoundaries]
    )

    private static let weekdayAliasToEnglish: [String: String] = [
        "monday": "monday", "mon": "monday", "pazartesi": "monday",
        "tuesday": "tuesday", "tue": "tuesday", "tues": "tuesday", "sali": "tuesday", "salı": "tuesday",
        "wednesday": "wednesday", "wed": "wednesday", "carsamba": "wednesday", "çarşamba": "wednesday",
        "thursday": "thursday", "thu": "thursday", "thur": "thursday", "thurs": "thursday", "persembe": "thursday", "perşembe": "thursday",
        "friday": "friday", "fri": "friday", "cuma": "friday",
        "saturday": "saturday", "sat": "saturday", "cumartesi": "saturday",
        "sunday": "sunday", "sun": "sunday", "pazar": "sunday"
    ]

    private static let weekdayAliasToNumber: [String: Int] = [
        "sunday": 1, "sun": 1, "pazar": 1,
        "monday": 2, "mon": 2, "pazartesi": 2,
        "tuesday": 3, "tue": 3, "tues": 3, "sali": 3, "salı": 3,
        "wednesday": 4, "wed": 4, "carsamba": 4, "çarşamba": 4,
        "thursday": 5, "thu": 5, "thur": 5, "thurs": 5, "persembe": 5, "perşembe": 5,
        "friday": 6, "fri": 6, "cuma": 6,
        "saturday": 7, "sat": 7, "cumartesi": 7
    ]

    private static let relativeInAfterRegex = try! NSRegularExpression(
        pattern: "(?i)\\b(?:in|after)\\s+(\\d+|half\\s+(?:an|a)|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\\s+(minute|minutes|min|mins|hour|hours|hr|hrs|day|days|week|weeks|month|months)\\b",
        options: [.useUnicodeWordBoundaries]
    )

    private static let relativeLaterRegex = try! NSRegularExpression(
        pattern: "(?i)\\b(\\d+|a|an|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\\s+(minute|minutes|min|mins|hour|hours|hr|hrs|day|days|week|weeks|month|months)\\s+(?:later|from\\s+now)\\b",
        options: [.useUnicodeWordBoundaries]
    )

    private static let turkishRelativeRegex = try! NSRegularExpression(
        pattern: "(?i)\\b(yarim|yarım|bir|iki|uc|dort|bes|alti|yedi|sekiz|dokuz|on|\\d+)\\s+(dakika|dk|saat|gun|gün|hafta|ay)(?:ya|ye|e|a|te|ta|de|da)?\\s*(sonra|icinde|içinde|icerisinde|içerisinde)?\\b",
        options: [.useUnicodeWordBoundaries]
    )
    
    private static let monthLexicon: [String: Int] = {
        var lexicon: [String: Int] = [:]
        let locales: [Locale] = [.autoupdatingCurrent, Locale(identifier: "en_US_POSIX"), Locale(identifier: "tr_TR")]
        for locale in locales {
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = locale
            for (index, name) in calendar.monthSymbols.enumerated() {
                lexicon[NLPDateTimeSanitizer.textNormalized(name)] = index + 1
            }
            for (index, name) in calendar.shortMonthSymbols.enumerated() {
                lexicon[NLPDateTimeSanitizer.textNormalized(name)] = index + 1
            }
        }
        return lexicon
    }()

    private static let monthPattern: String = {
        monthLexicon.keys
            .sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
    }()

    private static let suffixPattern = "(?:\\s*(?:de|da|te|ta))?"

    private static let dayMonthRegex = try! NSRegularExpression(pattern: "(?<!\\d)(\\d{1,2})\\s+(" + monthPattern + ")" + suffixPattern, options: [])
    private static let monthDayRegex = try! NSRegularExpression(pattern: "(" + monthPattern + ")" + suffixPattern + "\\s+(\\d{1,2})", options: [])

    private static let relativeDayMap: [String: String] = {
        var map: [String: String] = [:]
        let weekdays = ["monday","tuesday","wednesday","thursday","friday","saturday","sunday"]
        for day in weekdays {
            map[day] = day
            map["next_" + day] = "next_" + day
        }
        map["today"] = "today"
        map["tomorrow"] = "tomorrow"
        map["bugun"] = "today"
        map["yarin"] = "tomorrow"
        map["pazartesi"] = "monday"
        map["sali"] = "tuesday"
        map["carsamba"] = "wednesday"
        map["persembe"] = "thursday"
        map["cuma"] = "friday"
        map["cumartesi"] = "saturday"
        map["pazar"] = "sunday"
        map["haftaya"] = "next_monday"
        map["next_week"] = "next_monday"
        return map
    }()

    private static let relativeNumberWords: [String: Double] = [
        "a": 1,
        "an": 1,
        "one": 1,
        "half": 0.5,
        "two": 2,
        "three": 3,
        "four": 4,
        "five": 5,
        "six": 6,
        "seven": 7,
        "eight": 8,
        "nine": 9,
        "ten": 10,
        "eleven": 11,
        "twelve": 12,
        "yarim": 0.5,
        "bir": 1,
        "iki": 2,
        "uc": 3,
        "dort": 4,
        "bes": 5,
        "alti": 6,
        "yedi": 7,
        "sekiz": 8,
        "dokuz": 9,
        "on": 10
    ]
}

nonisolated private extension NLPDateTimeSanitizer {
    struct Detection<T> {
        var value: T?
        var invalidInput: String?
    }
    
    struct DateDetection {
        var date: Date?
        var invalidInput: String?
    }
    
    typealias TimeDetection = Detection<String>
    typealias DayDetection = Detection<String>
    
    static func detectDay(in texts: [String], candidate: String?, calendar: Calendar) -> DayDetection {
        for text in texts {
            if let numeric = detectNumericDate(in: text, calendar: calendar) {
                if let date = numeric.date {
                    return Detection(value: DateHelper.absoluteDayString(from: date), invalidInput: nil)
                }
                if let invalid = numeric.invalidInput {
                    return Detection(value: nil, invalidInput: invalid.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            if let word = detectWordDate(in: text, calendar: calendar) {
                if let date = word.date {
                    return Detection(value: DateHelper.absoluteDayString(from: date), invalidInput: nil)
                }
                if let invalid = word.invalidInput {
                    return Detection(value: nil, invalidInput: invalid.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            if let nextWeekday = detectNextWeekdayAlias(in: text) {
                return Detection(value: "next_" + nextWeekday, invalidInput: nil)
            }
            if let weekdayIndex = detectWeekdayToken(in: text),
               let date = upcomingWeekdayDate(weekday: weekdayIndex, calendar: calendar) {
                return Detection(value: DateHelper.absoluteDayString(from: date), invalidInput: nil)
            }
            if let relativeDay = detectRelativeDayKeyword(in: text) {
                return Detection(value: relativeDay, invalidInput: nil)
            }
        }
        return normalizeCandidateDay(candidate, calendar: calendar)
    }

    static func detectTime(in texts: [String], candidate: String?, period: TimePeriod?) -> TimeDetection {
        for text in texts {
            if let colon = detectColonTime(in: text) {
                if colon.value != nil || colon.invalidInput != nil { return colon }
            }
            if let keyword = detectKeywordTime(in: text, period: period) {
                if keyword.value != nil || keyword.invalidInput != nil { return keyword }
            }
            if let prefixed = detectPeriodPrefixedTime(in: text, period: period) {
                if prefixed.value != nil || prefixed.invalidInput != nil { return prefixed }
            }
            // Check for standalone keywords (e.g. "morning", "evening") without numbers
            if let standalone = detectStandaloneTimeKeyword(in: text) {
                return standalone
            }
        }
        return normalizeCandidateTime(candidate, period: period)
    }

    static func detectStandaloneTimeKeyword(in text: String) -> TimeDetection? {
        let normalized = textNormalized(text)
        
        // Sabah / Morning -> 08:00
        let morningPatterns = ["sabah", "morning", "matin", "manha", "manana"]
        for pattern in morningPatterns {
            if normalized.contains(pattern) {
                return Detection(value: "08:00", invalidInput: nil)
            }
        }
        
        // Evening -> 20:00
        let eveningPatterns = ["aksam", "akşam", "evening", "bu aksam", "bu akşam", "tonight", "soir", "abend", "tarde", "noite"]
        for pattern in eveningPatterns {
            if normalized.contains(pattern) {
                return Detection(value: "20:00", invalidInput: nil)
            }
        }
        
        // Gece / Night -> 00:00
        let nightPatterns = ["gece", "night", "midnight", "nuit", "nacht", "gece yarisi", "gece yarısı"]
        for pattern in nightPatterns {
            if normalized.contains(pattern) {
                return Detection(value: "00:00", invalidInput: nil)
            }
        }
        
        // Noon -> 12:00
        let noonPatterns = ["oglen", "öğlen", "noon", "midday", "midi", "mediodia"]
        for pattern in noonPatterns {
            if normalized.contains(pattern) {
                return Detection(value: "12:00", invalidInput: nil)
            }
        }
        
        return nil
    }

    static func detectColonTime(in text: String) -> TimeDetection? {
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = colonTimeRegex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        let token = text.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let hour = match.intValue(in: text, at: 1),
                  let minute = match.intValue(in: text, at: 2) else {
            return Detection(value: nil, invalidInput: token)
            }
        guard let formatted = format(hour: hour, minute: minute) else {
            return Detection(value: nil, invalidInput: token)
        }
        return Detection(value: formatted, invalidInput: nil)
    }

    static func detectKeywordTime(in text: String, period: TimePeriod?) -> TimeDetection? {
        let normalized = textNormalized(text)
        let range = NSRange(location: 0, length: normalized.utf16.count)
        if let match = keywordTimeRegex.firstMatch(in: normalized, options: [], range: range) {
            let token = normalized.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let hour = match.intValue(in: normalized, at: 1) else {
                return Detection(value: nil, invalidInput: token)
            }
            if let minute = match.intValue(in: normalized, at: 2) {
                guard let formatted = format(hour: hour, minute: minute) else {
                    return Detection(value: nil, invalidInput: token)
                }
                return Detection(value: formatted, invalidInput: nil)
            }
            guard let formatted = formatHour(hour, period: period) else {
                return Detection(value: nil, invalidInput: token)
            }
            return Detection(value: formatted, invalidInput: nil)
        }

        if let match = apostropheTimeRegex.firstMatch(in: normalized, options: [], range: range) {
            let token = normalized.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let hour = match.intValue(in: normalized, at: 1),
                  let formatted = formatHour(hour, period: period) else {
                return Detection(value: nil, invalidInput: token)
            }
            return Detection(value: formatted, invalidInput: nil)
        }

        if let match = ampmRegex.firstMatch(in: normalized, options: [], range: range) {
            let token = normalized.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let hour = match.intValue(in: normalized, at: 1) else {
                return Detection(value: nil, invalidInput: token)
            }
            let suffix = normalized.substring(with: match.range(at: 2))
            let periodOverride: TimePeriod = suffix.contains("p") ? .pm : .am
            guard let formatted = formatHour(hour, period: periodOverride) else {
                return Detection(value: nil, invalidInput: token)
            }
            return Detection(value: formatted, invalidInput: nil)
        }

        return nil
    }

    static func detectPeriodPrefixedTime(in text: String, period: TimePeriod?) -> TimeDetection? {
        let normalized = textNormalized(text)
        let range = NSRange(location: 0, length: normalized.utf16.count)
        guard let match = periodPrefixedRegex.firstMatch(in: normalized, options: [], range: range) else {
                return nil
            }
        let token = normalized.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hour = match.intValue(in: normalized, at: 2) else {
            return Detection(value: nil, invalidInput: token)
            }
            let keyword = normalized.substring(with: match.range(at: 1))
            let inferred = periodOverride(for: keyword) ?? period
        if let inferred = inferred, (inferred == .am || inferred == .pm), !(1...12).contains(hour) {
            return Detection(value: nil, invalidInput: token)
        }
            if let minute = match.intValue(in: normalized, at: 3) {
                let resolvedHour = apply(period: inferred, to: hour)
            guard let formatted = format(hour: resolvedHour, minute: minute) else {
                return Detection(value: nil, invalidInput: token)
            }
            return Detection(value: formatted, invalidInput: nil)
        }
        guard let formatted = formatHour(hour, period: inferred) else {
            return Detection(value: nil, invalidInput: token)
        }
        return Detection(value: formatted, invalidInput: nil)
    }

    static func detectNumericDate(in text: String, calendar: Calendar) -> DateDetection? {
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = numericDateRegex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        let token = text.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = match.intValue(in: text, at: 1),
              let second = match.intValue(in: text, at: 3) else {
            return DateDetection(date: nil, invalidInput: token)
        }
        let separator = text.substring(with: match.range(at: 2))
        let yearString = text.substring(with: match.range(at: 4))
        let localePrefersMonthFirst = usesMonthFirst(locale: Locale.current)
        var dayFirst = separator == "."
        if separator == "/" {
            dayFirst = !localePrefersMonthFirst
        }
        var day = dayFirst ? first : second
        var month = dayFirst ? second : first
        if month > 12, day <= 12 {
            swap(&day, &month)
        }
        if !(1...31).contains(day) || !(1...12).contains(month) {
            return DateDetection(date: nil, invalidInput: token)
        }
        let year: Int? = {
            guard !yearString.isEmpty else { return nil }
            guard let value = Int(yearString) else { return nil }
            if yearString.count == 2 {
                return value + (value >= 70 ? 1900 : 2000)
            }
            return value
        }()
        guard let date = makeDate(day: day, month: month, year: year, calendar: calendar) else {
            return DateDetection(date: nil, invalidInput: token)
        }
        return DateDetection(date: date, invalidInput: nil)
    }
    
    static func detectWordDate(in text: String, calendar: Calendar) -> DateDetection? {
        let normalized = textNormalized(text)
        let nsRange = NSRange(location: 0, length: (normalized as NSString).length)
        if let match = dayMonthRegex.firstMatch(in: normalized, options: [], range: nsRange) {
            let token = normalized.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let day = match.intValue(in: normalized, at: 1) else {
                return DateDetection(date: nil, invalidInput: token)
            }
            let monthName = normalized.substring(with: match.range(at: 2))
            guard let month = monthLexicon[monthName] else {
                return DateDetection(date: nil, invalidInput: token)
            }
            guard let date = makeDate(day: day, month: month, year: nil, calendar: calendar) else {
                return DateDetection(date: nil, invalidInput: token)
            }
            return DateDetection(date: date, invalidInput: nil)
        }
        if let match = monthDayRegex.firstMatch(in: normalized, options: [], range: nsRange) {
            let token = normalized.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let day = match.intValue(in: normalized, at: 2) else {
                return DateDetection(date: nil, invalidInput: token)
            }
            let monthName = normalized.substring(with: match.range(at: 1))
            guard let month = monthLexicon[monthName] else {
                return DateDetection(date: nil, invalidInput: token)
            }
            guard let date = makeDate(day: day, month: month, year: nil, calendar: calendar) else {
                return DateDetection(date: nil, invalidInput: token)
            }
            return DateDetection(date: date, invalidInput: nil)
        }
        return nil
    }

    static func normalizeCandidateDay(_ candidate: String?, calendar: Calendar) -> DayDetection {
        guard let candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty else {
            return Detection(value: nil, invalidInput: nil)
        }
        let normalized = normalizedToken(candidate)
        if let mapped = relativeDayMap[normalized] {
            return Detection(value: mapped, invalidInput: nil)
        }
        if let iso = parseAbsoluteLabel(candidate) {
            return Detection(value: iso, invalidInput: nil)
        }
        if let numeric = detectNumericDate(in: candidate, calendar: calendar) {
            if let date = numeric.date {
                return Detection(value: DateHelper.absoluteDayString(from: date), invalidInput: nil)
            }
            if let invalid = numeric.invalidInput {
                return Detection(value: nil, invalidInput: invalid)
            }
        }
        if let word = detectWordDate(in: candidate, calendar: calendar) {
            if let date = word.date {
                return Detection(value: DateHelper.absoluteDayString(from: date), invalidInput: nil)
            }
            if let invalid = word.invalidInput {
                return Detection(value: nil, invalidInput: invalid)
            }
        }
        if let natural = parseNaturalDate(candidate, calendar: calendar) {
            if let date = natural.date {
                return Detection(value: DateHelper.absoluteDayString(from: date), invalidInput: nil)
            }
            if let invalid = natural.invalidInput {
                return Detection(value: nil, invalidInput: invalid)
            }
        }
        return Detection(value: nil, invalidInput: candidate)
    }
    
    static func detectRelativeOffset(in texts: [String], calendar: Calendar) -> (date: Date, unit: RelativeUnit)? {
        for text in texts {
            if let match = relativeOffsetDate(from: text, calendar: calendar) {
                return match
            }
        }
        return nil
    }
    
    static func detectNextWeekdayAlias(in text: String) -> String? {
        let normalized = textNormalized(text)
        let range = NSRange(location: 0, length: normalized.utf16.count)
        if let match = nextWeekdayRegex.firstMatch(in: normalized, options: [], range: range) {
            let token = normalized.substring(with: match.range(at: 1))
            if let english = weekdayAliasToEnglish[token] {
                return english
            }
        }
        return nil
    }

    static func detectWeekdayToken(in text: String) -> Int? {
        let normalized = textNormalized(text)
        let range = NSRange(location: 0, length: normalized.utf16.count)
        if let match = dayNameRegex.firstMatch(in: normalized, options: [], range: range) {
            let token = normalized.substring(with: match.range(at: 0))
            return weekdayAliasToNumber[token]
        }
        return nil
    }
    
    static func detectRelativeDayKeyword(in text: String) -> String? {
        let normalized = textNormalized(text)
        for (key, mapped) in relativeDayMap {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: key) + "\\b"
            if normalized.range(of: pattern, options: .regularExpression) != nil {
                return mapped
            }
        }
        return nil
    }

    static func upcomingWeekdayDate(weekday: Int, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: Date())
        let currentWeekday = calendar.component(.weekday, from: today)
        let daysToAdd = (weekday - currentWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: daysToAdd, to: today)
    }

    static func normalizeCandidateTime(_ candidate: String?, period: TimePeriod?) -> TimeDetection {
        guard var candidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty else {
            return Detection(value: nil, invalidInput: nil)
        }
        candidate = candidate.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        candidate = candidate.replacingOccurrences(of: ".", with: ":")
        if let _ = candidate.range(of: "^\\d{1,2}:\\d{1,2}$", options: .regularExpression) {
            let parts = candidate.split(separator: ":")
            guard parts.count == 2,
                  let hour = Int(parts[0]),
                  let minute = Int(parts[1]),
                  let formatted = format(hour: hour, minute: minute) else {
                return Detection(value: nil, invalidInput: candidate)
            }
            return Detection(value: formatted, invalidInput: nil)
        }
        if let _ = candidate.range(of: "^\\d{1,2}$", options: .regularExpression) {
            guard let hour = Int(candidate), let formatted = format(hour: hour, minute: 0) else {
                return Detection(value: nil, invalidInput: candidate)
            }
            return Detection(value: formatted, invalidInput: nil)
        }
        let compact = candidate.replacingOccurrences(of: " ", with: "")
        if let match = compact.range(of: "^(\\d{1,2})(a|p)m$", options: [.regularExpression, .caseInsensitive]) {
            let token = String(compact[match])
            let hourString = token.prefix { $0.isNumber }
            guard let hour = Int(hourString) else {
                return Detection(value: nil, invalidInput: candidate)
            }
            let suffix = token.lowercased().contains("p") ? TimePeriod.pm : TimePeriod.am
            guard let formatted = formatHour(hour, period: suffix) else {
                return Detection(value: nil, invalidInput: candidate)
            }
            return Detection(value: formatted, invalidInput: nil)
        }
        return Detection(value: nil, invalidInput: nil)
    }

    static func relativeOffsetDate(from text: String, calendar: Calendar) -> (date: Date, unit: RelativeUnit)? {
        let normalized = textNormalized(text)
        
        // Quick catch for "half hour ..." even if suffixes or missing "later"
        if normalized.range(of: "\\byarim\\s+saat", options: .regularExpression) != nil {
            if let date = apply(relativeValue: 0.5, unit: .hour, calendar: calendar) {
                return (date, .hour)
            }
        }
        
        if let parsed = parseRelativeMatch(in: normalized, regex: relativeInAfterRegex) {
            if let date = apply(relativeValue: parsed.value, unit: parsed.unit, calendar: calendar) {
                return (date, parsed.unit)
            }
        }
        if let parsed = parseRelativeMatch(in: normalized, regex: relativeLaterRegex) {
            if let date = apply(relativeValue: parsed.value, unit: parsed.unit, calendar: calendar) {
                return (date, parsed.unit)
            }
        }
        if let parsed = parseRelativeMatch(in: normalized, regex: turkishRelativeRegex) {
            if let date = apply(relativeValue: parsed.value, unit: parsed.unit, calendar: calendar) {
                return (date, parsed.unit)
            }
        }
        return nil
    }
    
    // Heuristic fallback for relative expressions that slip past regex
    static func detectSimpleRelative(in texts: [String], calendar: Calendar) -> (date: Date, unit: RelativeUnit)? {
        for text in texts {
            let normalized = textNormalized(text)
            guard normalized.contains("sonra") || normalized.contains("icinde") || normalized.contains("içinde") else { continue }
            
            let value: Double? = {
                if normalized.contains("yarim") || normalized.contains("yarım") || normalized.contains("half") { return 0.5 }
                return TextParsingHelpers.extractFirstNumber(from: normalized)
            }()
            
            guard let relativeValue = value, relativeValue > 0 else { continue }
            
            let unit: RelativeUnit? = {
                if normalized.contains("saat") || normalized.contains("hour") { return .hour }
                if normalized.contains("dk") || normalized.contains("dakika") || normalized.contains("minute") { return .minute }
                if normalized.contains("hafta") || normalized.contains("week") { return .week }
                if normalized.contains("ay") || normalized.contains("month") { return .month }
                if normalized.contains("gun") || normalized.contains("gün") || normalized.contains("day") { return .day }
                return nil
            }()
            
            guard let unit = unit else { continue }
            if let date = apply(relativeValue: relativeValue, unit: unit, calendar: calendar) {
                return (date, unit)
            }
        }
        return nil
    }

    static func parseRelativeMatch(in text: String, regex: NSRegularExpression) -> (value: Double, unit: RelativeUnit)? {
        let range = NSRange(location: 0, length: text.utf16.count)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        let quantityToken = text.substring(with: match.range(at: 1))
        var unitToken = text.substring(with: match.range(at: 2))
        guard let value = parseRelativeValue(from: quantityToken), value > 0 else {
            return nil
        }
        var unit = RelativeUnit(token: unitToken)
        if unit == nil {
            // Try stripping Turkish case/ suffixes like -e/-a/-ya
            unitToken = unitToken.replacingOccurrences(of: "(ya|ye|e|a)$", with: "", options: [.regularExpression, .caseInsensitive])
            unit = RelativeUnit(token: unitToken)
        }
        guard let resolvedUnit = unit else {
            return nil
        }
        return (value, resolvedUnit)
    }

    static func parseRelativeValue(from token: String) -> Double? {
        let normalized = token.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return nil }
        if let number = Double(normalized) {
            return number
        }
        if normalized.contains("half") || normalized.contains("yarim") {
            return 0.5
        }
        if let mapped = relativeNumberWords[normalized] {
            return mapped
        }
        return nil
    }

    static func apply(relativeValue: Double, unit: RelativeUnit, calendar: Calendar) -> Date? {
        let now = Date()
        switch unit {
        case .minute:
            return now.addingTimeInterval(relativeValue * 60)
        case .hour:
            return now.addingTimeInterval(relativeValue * 3_600)
        case .day:
            guard relativeValue.truncatingRemainder(dividingBy: 1) == 0 else { return nil }
            var components = DateComponents()
            components.day = Int(relativeValue)
            return calendar.date(byAdding: components, to: now)
        case .week:
            guard relativeValue.truncatingRemainder(dividingBy: 1) == 0 else { return nil }
            var components = DateComponents()
            components.day = Int(relativeValue) * 7
            return calendar.date(byAdding: components, to: now)
        case .month:
            guard relativeValue.truncatingRemainder(dividingBy: 1) == 0 else { return nil }
            var components = DateComponents()
            components.month = Int(relativeValue)
            return calendar.date(byAdding: components, to: now)
        }
    }

    static func parseAbsoluteLabel(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: trimmed) {
                return formatter.string(from: date)
            }
        }
        return nil
    }

    static func formatHour(_ hour: Int, period: TimePeriod?) -> String? {
        if let period = period {
            guard (1...12).contains(hour) else {
                return nil
            }
            switch period {
            case .am:
                let adjusted = hour == 12 ? 0 : hour
                return format(hour: adjusted, minute: 0)
            case .pm:
                let adjusted = hour == 12 ? 12 : hour + 12
                return format(hour: adjusted, minute: 0)
            case .noon:
                return format(hour: 12, minute: 0)
            case .midnight:
                return format(hour: 0, minute: 0)
            }
        }
        return format(hour: hour, minute: 0)
    }

    static func format(hour: Int, minute: Int) -> String? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    static func apply(period: TimePeriod?, to hour: Int) -> Int {
        guard (0...23).contains(hour) else { return hour }
        guard let period = period else { return hour }
        switch period {
        case .am:
            return hour == 12 ? 0 : hour
        case .pm:
            return hour < 12 ? hour + 12 : hour
        case .noon:
            return 12
        case .midnight:
            return 0
        }
    }

    static func makeDate(day: Int, month: Int, year: Int?, calendar: Calendar) -> Date? {
        var calendar = calendar
        let currentYear = calendar.component(.year, from: Date())
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        var components = DateComponents()
        components.day = day
        components.month = month
        components.year = year ?? currentYear
        guard let date = calendar.date(from: components) else {
            return nil
        }
        let resolvedDay = calendar.component(.day, from: date)
        let resolvedMonth = calendar.component(.month, from: date)
        if resolvedDay != day || resolvedMonth != month {
            return nil
        }
        if year == nil, date < Date() {
            components.year = (components.year ?? 0) + 1
            guard let future = calendar.date(from: components) else {
                return nil
            }
            return future
        }
        return date
    }

    static func detectPeriod(in texts: [String]) -> TimePeriod? {
        for text in texts {
            let normalized = textNormalized(text)
            if containsKeyword(normalized, in: midnightKeywords) { return .midnight }
            if containsKeyword(normalized, in: noonKeywords) { return .noon }
            if containsKeyword(normalized, in: pmKeywords) { return .pm }
            if containsKeyword(normalized, in: amKeywords) { return .am }
        }
        return nil
    }

    static func containsKeyword(_ text: String, in keywords: [String]) -> Bool {
        for keyword in keywords where text.contains(keyword) {
            return true
        }
        return false
    }

    static func periodOverride(for keyword: String) -> TimePeriod? {
        if midnightKeywords.contains(where: { keyword.contains($0) }) { return .midnight }
        if noonKeywords.contains(where: { keyword.contains($0) }) { return .noon }
        if pmKeywords.contains(where: { keyword.contains($0) }) { return .pm }
        if amKeywords.contains(where: { keyword.contains($0) }) { return .am }
        return nil
    }

    static func textNormalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }

    static func normalizedToken(_ text: String) -> String {
        textNormalized(text)
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    static func usesMonthFirst(locale: Locale) -> Bool {
        guard let format = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: locale) else {
            return false
        }
        if let mIndex = format.firstIndex(of: "M"), let dIndex = format.firstIndex(of: "d") {
            return mIndex < dIndex
        }
        return false
    }
    
    static func parseNaturalDate(_ text: String, calendar: Calendar) -> DateDetection? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let formatters: [DateFormatter] = [
            // Formats with year
            createFormatter(format: "d MMM yyyy", locale: Locale.current), // "30 nov 2025"
            createFormatter(format: "d MMMM yyyy", locale: Locale.current), // "30 november 2025"
            createFormatter(format: "MMM d yyyy", locale: Locale.current),   // "nov 30 2025"
            createFormatter(format: "MMMM d yyyy", locale: Locale.current),  // "november 30 2025"
            createFormatter(format: "d MMM yyyy", locale: Locale(identifier: "en_US_POSIX")),
            createFormatter(format: "d MMMM yyyy", locale: Locale(identifier: "en_US_POSIX")),
            createFormatter(format: "MMM d yyyy", locale: Locale(identifier: "en_US_POSIX")),
            createFormatter(format: "MMMM d yyyy", locale: Locale(identifier: "en_US_POSIX")),
            // Formats without year
            createFormatter(format: "d MMMM", locale: Locale.current),
            createFormatter(format: "d MMM", locale: Locale.current),
            createFormatter(format: "MMMM d", locale: Locale.current),
            createFormatter(format: "MMM d", locale: Locale.current),
            createFormatter(format: "d MMMM", locale: Locale(identifier: "en_US_POSIX")),
            createFormatter(format: "d MMM", locale: Locale(identifier: "en_US_POSIX")),
            createFormatter(format: "MMMM d", locale: Locale(identifier: "en_US_POSIX")),
            createFormatter(format: "MMM d", locale: Locale(identifier: "en_US_POSIX"))
        ]
        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        for formatter in formatters {
            if let date = formatter.date(from: normalized) {
                // Check if formatter includes year (4-digit year formats)
                let components = calendar.dateComponents([.day, .month, .year], from: date)
                
                // If year is present and reasonable (1900-2100), use it
                if let year = components.year, year >= 1900 && year <= 2100 {
                    if let finalDate = calendar.date(from: components) {
                        return DateDetection(date: finalDate, invalidInput: nil)
                    }
                }
                
                // Otherwise, set to current year (or next year if date has passed)
                var dateComponents = calendar.dateComponents([.day, .month], from: date)
                let parsedDay = dateComponents.day
                let parsedMonth = dateComponents.month
                dateComponents.year = currentYear
                if let dateWithYear = calendar.date(from: dateComponents) {
                    let resolvedDay = calendar.component(.day, from: dateWithYear)
                    let resolvedMonth = calendar.component(.month, from: dateWithYear)
                    if let day = parsedDay, let month = parsedMonth,
                       resolvedDay != day || resolvedMonth != month {
                        return DateDetection(date: nil, invalidInput: normalized.isEmpty ? nil : normalized)
                    }
                    if dateWithYear < now {
                        dateComponents.year = currentYear + 1
                        if let future = calendar.date(from: dateComponents) {
                            let futureDay = calendar.component(.day, from: future)
                            let futureMonth = calendar.component(.month, from: future)
                            if let day = parsedDay, let month = parsedMonth,
                               futureDay != day || futureMonth != month {
                                return DateDetection(date: nil, invalidInput: normalized.isEmpty ? nil : normalized)
                            }
                            return DateDetection(date: future, invalidInput: nil)
                        }
                    } else {
                        return DateDetection(date: dateWithYear, invalidInput: nil)
                    }
                }
            }
        }
        return DateDetection(date: nil, invalidInput: normalized.isEmpty ? nil : normalized)
    }
    
    static func createFormatter(format: String, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.isLenient = false
        return formatter
    }
    
    nonisolated static func replaceMatches(in text: String, regexes: [NSRegularExpression]) -> String {
        guard !text.isEmpty else { return text }
        var mutable = text
        for regex in regexes {
            let range = NSRange(location: 0, length: mutable.utf16.count)
            mutable = regex.stringByReplacingMatches(in: mutable, options: [], range: range, withTemplate: " ")
        }
        return mutable
    }
}

nonisolated private enum TimePeriod {
    case am
    case pm
    case noon
    case midnight
}

nonisolated private enum RelativeUnit {
    case minute
    case hour
    case day
    case week
    case month
    
    init?(token: String) {
        let normalized = token
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized {
        case "minute", "minutes", "min", "mins", "dakika", "dk":
            self = .minute
        case "hour", "hours", "hr", "hrs", "saat":
            self = .hour
        case "day", "days", "gun":
            self = .day
        case "week", "weeks", "hafta":
            self = .week
        case "month", "months", "ay":
            self = .month
        default:
            return nil
        }
    }
}


nonisolated private extension NSTextCheckingResult {
    nonisolated func intValue(in text: String, at index: Int) -> Int? {
        let substring = self.substring(in: text, at: index)
        return Int(substring)
    }

    nonisolated func substring(in text: String, at index: Int) -> String {
        guard index < numberOfRanges else { return "" }
        let range = self.range(at: index)
        guard let swiftRange = Range(range, in: text) else { return "" }
        return String(text[swiftRange])
    }
}

nonisolated private extension String {
    nonisolated func substring(with range: NSRange) -> String {
        guard let swiftRange = Range(range, in: self) else { return "" }
        return String(self[swiftRange])
    }
}
