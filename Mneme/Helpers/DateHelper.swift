import Foundation

nonisolated struct DateHelper {
    private static let absoluteDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    nonisolated(unsafe) private static let isoDateTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private static let weekdayKeywordMap: [String: Int] = [
        "sunday": 1, "sun": 1, "pazar": 1,
        "monday": 2, "mon": 2, "pazartesi": 2,
        "tuesday": 3, "tue": 3, "tues": 3, "sali": 3, "salı": 3,
        "wednesday": 4, "wed": 4, "carsamba": 4, "çarşamba": 4,
        "thursday": 5, "thu": 5, "thur": 5, "thurs": 5, "persembe": 5, "perşembe": 5,
        "friday": 6, "fri": 6, "cuma": 6,
        "saturday": 7, "sat": 7, "cumartesi": 7
    ]

    nonisolated static func parseDate(
        dayLabel: String?,
        timeString: String?,
        calendar: Calendar = .current
    ) -> Date? {
        let now = Date()
        var date = calendar.startOfDay(for: now)
        var dayWasExplicit = false
        
        // Parse day
        var parsedAbsolute: Date? = nil
        if let dayLabel = dayLabel {
            if let absolute = dateFromAbsoluteLabel(dayLabel) {
                dayWasExplicit = true
                parsedAbsolute = absolute
                date = calendar.startOfDay(for: absolute)
            } else if let parsed = parseDay(dayLabel: dayLabel, calendar: calendar) {
                dayWasExplicit = true
                date = parsed
            }
        }
        
        // Parse time
        if let timeString = timeString {
            let components = timeString.split(separator: ":")
            if components.count == 2,
               let hour = Int(components[0]),
               let minute = Int(components[1]) {
                if let absolute = parsedAbsolute {
                    date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: absolute) ?? absolute
                } else {
                    date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
                }
            }
        }
        
        // If date is in the past and no day was specified, assume tomorrow
        if !dayWasExplicit && date < now {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }
        
        return date
    }
    
    nonisolated private static func parseDay(dayLabel: String, calendar: Calendar) -> Date? {
        let now = Date()
        let today = calendar.startOfDay(for: now)
        
        if let absoluteDate = dateFromAbsoluteLabel(dayLabel) {
            return calendar.startOfDay(for: absoluteDate)
        }
        
        // Try parsing date formats like "22 november", "22 nov", "november 22", etc.
        if let parsedDate = parseNaturalDate(dayLabel, calendar: calendar) {
            return parsedDate
        }

        let normalizedLabel = dayLabel.lowercased()
        
        if let forcedWeekday = extractWeekday(from: normalizedLabel),
           containsNextIndicator(in: normalizedLabel) {
            return nextWeekday(
                weekday: forcedWeekday,
                from: today,
                calendar: calendar,
                allowToday: false,
                forceFollowingWeek: true
            )
        }

        switch normalizedLabel {
        case "today":
            return today
            
        case "tomorrow", "yarın", "yarin":
            return calendar.date(byAdding: .day, value: 1, to: today)
            
        case "haftaya", "next week", "gelecek hafta":
            // "Haftaya" means 7 days from now (next week, same day)
            return calendar.date(byAdding: .day, value: 7, to: today)
            
        case "monday":
            return nextWeekday(weekday: 2, from: today, calendar: calendar, allowToday: true)
        case "tuesday":
            return nextWeekday(weekday: 3, from: today, calendar: calendar, allowToday: true)
        case "wednesday":
            return nextWeekday(weekday: 4, from: today, calendar: calendar, allowToday: true)
        case "thursday":
            return nextWeekday(weekday: 5, from: today, calendar: calendar, allowToday: true)
        case "friday":
            return nextWeekday(weekday: 6, from: today, calendar: calendar, allowToday: true)
        case "saturday":
            return nextWeekday(weekday: 7, from: today, calendar: calendar, allowToday: true)
        case "sunday":
            return nextWeekday(weekday: 1, from: today, calendar: calendar, allowToday: true)
            
        case "next_monday":
            return nextWeekday(weekday: 2, from: today, calendar: calendar, allowToday: false, forceFollowingWeek: true)
        case "next_tuesday":
            return nextWeekday(weekday: 3, from: today, calendar: calendar, allowToday: false, forceFollowingWeek: true)
        case "next_wednesday":
            return nextWeekday(weekday: 4, from: today, calendar: calendar, allowToday: false, forceFollowingWeek: true)
        case "next_thursday":
            return nextWeekday(weekday: 5, from: today, calendar: calendar, allowToday: false, forceFollowingWeek: true)
        case "next_friday":
            return nextWeekday(weekday: 6, from: today, calendar: calendar, allowToday: false, forceFollowingWeek: true)
        case "next_saturday":
            return nextWeekday(weekday: 7, from: today, calendar: calendar, allowToday: false, forceFollowingWeek: true)
        case "next_sunday":
            return nextWeekday(weekday: 1, from: today, calendar: calendar, allowToday: false, forceFollowingWeek: true)
            
        case "weekday_monday":
            return nextWeekday(weekday: 2, from: today, calendar: calendar, allowToday: true)
        case "weekday_tuesday":
            return nextWeekday(weekday: 3, from: today, calendar: calendar, allowToday: true)
        case "weekday_wednesday":
            return nextWeekday(weekday: 4, from: today, calendar: calendar, allowToday: true)
        case "weekday_thursday":
            return nextWeekday(weekday: 5, from: today, calendar: calendar, allowToday: true)
        case "weekday_friday":
            return nextWeekday(weekday: 6, from: today, calendar: calendar, allowToday: true)
        case "weekday_saturday":
            return nextWeekday(weekday: 7, from: today, calendar: calendar, allowToday: true)
        case "weekday_sunday":
            return nextWeekday(weekday: 1, from: today, calendar: calendar, allowToday: true)
            
        default:
            if let absoluteDate = dateFromAbsoluteLabel(dayLabel) {
                return calendar.startOfDay(for: absoluteDate)
            }
            return nil
        }
    }
    
    nonisolated private static func nextWeekday(
        weekday: Int,
        from date: Date,
        calendar: Calendar,
        allowToday: Bool = false,
        forceFollowingWeek: Bool = false
    ) -> Date? {
        let currentWeekday = calendar.component(.weekday, from: date)
        
        if allowToday && currentWeekday == weekday {
            return date
        }
        
        let daysToAdd: Int
        if currentWeekday < weekday {
            daysToAdd = weekday - currentWeekday
        } else if currentWeekday == weekday {
            daysToAdd = allowToday ? 0 : 7
        } else {
            daysToAdd = 7 - (currentWeekday - weekday)
        }
        
        let baseDate = calendar.date(byAdding: .day, value: daysToAdd, to: date)
        guard let base = baseDate else { return nil }
        
        if forceFollowingWeek {
            return calendar.date(byAdding: .day, value: 7, to: base)
        }
        return base
    }
    
    private static func parseNaturalDate(_ text: String, calendar: Calendar) -> Date? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Try various date formats (including year formats)
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
            createFormatter(format: "d MMMM", locale: Locale.current), // "22 november"
            createFormatter(format: "d MMM", locale: Locale.current),  // "22 nov"
            createFormatter(format: "MMMM d", locale: Locale.current),  // "november 22"
            createFormatter(format: "MMM d", locale: Locale.current),   // "nov 22"
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
                    return calendar.date(from: components)
                }
                
                // Otherwise, set to current year (or next year if date has passed)
                var dateComponents = calendar.dateComponents([.day, .month], from: date)
                dateComponents.year = currentYear
                
                if let dateWithYear = calendar.date(from: dateComponents) {
                    // If date is in the past, use next year
                    if dateWithYear < now {
                        dateComponents.year = currentYear + 1
                        return calendar.date(from: dateComponents)
                    }
                    return dateWithYear
                }
            }
        }
        
        return nil
    }
    
    private static func createFormatter(format: String, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.isLenient = false  // Strict parsing - reject invalid dates like "31 November"
        return formatter
    }
    
    private static func extractWeekday(from label: String) -> Int? {
        for (keyword, index) in weekdayKeywordMap where label.contains(keyword) {
            return index
        }
        return nil
    }
    
    private static func containsNextIndicator(in label: String) -> Bool {
        label.contains("next") || label.contains("haftaya") || label.contains("coming")
    }
    
    static func calculateElapsedTime(from startTime: String) -> String {
        let components = startTime.split(separator: ":")
        guard components.count == 2,
              let startHour = Int(components[0]),
              let startMinute = Int(components[1]) else {
            return "Unknown"
        }
        
        let calendar = Calendar.current
        let now = Date()
        let startTotalMinutes = startHour * 60 + startMinute
        let currentTotalMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        
        var elapsedMinutes = currentTotalMinutes - startTotalMinutes
        if elapsedMinutes < 0 {
            elapsedMinutes += 24 * 60
        }
        
        let hours = elapsedMinutes / 60
        let minutes = elapsedMinutes % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    nonisolated static func applyTimeFormat(_ formatter: DateFormatter, format: TimeFormat? = nil) {
        let selectedFormat = format ?? (UserDefaults.standard.string(forKey: "timeFormat").flatMap(TimeFormat.init) ?? .twentyFourHour)
        
        switch selectedFormat {
        case .twelveHour:
            formatter.locale = Locale(identifier: "en_US_POSIX")
            // This is a bit tricky with dateStyle/timeStyle. 
            // If they used dateFormat, we'd change it. 
            // For now, let's just set the locale to one that uses 12h.
            formatter.locale = Locale(identifier: "en_US")
        case .twentyFourHour:
            formatter.locale = Locale(identifier: "en_GB")
        }
    }
    
    nonisolated static func applyDateFormat(_ formatter: DateFormatter, format: AppDateFormat? = nil) {
        let selectedFormat = format ?? (UserDefaults.standard.string(forKey: "dateFormat").flatMap(AppDateFormat.init) ?? .systemDefault)
        
        if let formatString = selectedFormat.formatString {
            formatter.dateFormat = formatString
        }
    }
    
    nonisolated static func applySettings(_ formatter: DateFormatter) {
        let datePref = UserDefaults.standard.string(forKey: "dateFormat").flatMap(AppDateFormat.init) ?? .systemDefault
        let timePref = UserDefaults.standard.string(forKey: "timeFormat").flatMap(TimeFormat.init) ?? .twentyFourHour
        
        if let dateStr = datePref.formatString {
            if formatter.timeStyle != .none {
                let timePart = (timePref == .twelveHour) ? "h:mm a" : "HH:mm"
                formatter.dateFormat = "\(dateStr) \(timePart)"
            } else {
                formatter.dateFormat = dateStr
            }
        } else {
            applyTimeFormat(formatter, format: timePref)
        }
    }
}

nonisolated extension DateHelper {
    nonisolated static func absoluteDayString(from date: Date?) -> String? {
        guard let date else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    nonisolated static func absoluteDate(from label: String) -> Date? {
        dateFromAbsoluteLabel(label)
    }

    nonisolated private static func dateFromAbsoluteLabel(_ label: String) -> Date? {
        if let date = absoluteDayFormatter.date(from: label) {
            return date
        }

        if let date = isoDateTimeFormatter.date(from: label) {
            return date
        }

        return nil
    }
    
    nonisolated static func canParseTime(_ timeString: String) -> Bool {
        // Try to parse date/time using DateHelper.parseDate
        // Return true if successful
        if let _ = parseDate(dayLabel: nil, timeString: timeString) {
            return true
        }
        
        // Natural language expressions: "evening", "morning", "noon", "afternoon"
        let naturalTimeKeywords = [
            "morning", "sabah", "afternoon", "öğle", "öğleden sonra",
            "evening", "akşam", "night", "gece", "dawn", "şafak",
            "noon", "öğlen", "midday", "midnight", "gece yarısı"
        ]
        
        let lowercased = timeString.lowercased()
        return naturalTimeKeywords.contains(where: { lowercased.contains($0) })
    }
    
    nonisolated static func canParseDate(_ dateString: String) -> Bool {
        // First check absolute dates (YYYY-MM-DD)
        if let _ = absoluteDate(from: dateString) {
            return true
        }
        
        // Check using parseDate method
        // Return true if successfully parseable
        if let _ = parseDate(dayLabel: dateString, timeString: nil) {
            return true
        }
        
        return false
    }
}
