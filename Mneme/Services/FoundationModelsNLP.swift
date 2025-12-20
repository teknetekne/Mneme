import Foundation
import FoundationModels
import Translation

// MARK: - Foundation Models NLP Service

actor FoundationModelsNLP {
    static let shared = FoundationModelsNLP()
    
    private nonisolated let model: SystemLanguageModel
    
    init() {
        self.model = SystemLanguageModel.default
    }
    
    func parse(text raw: String) async -> PatternResult {
        // Validate text
        if !isValidText(raw) {
            return PatternResult()
        }
        
        if let variableResult = await resolveVariable(from: raw) {
            return variableResult
        }
        
        if let calorieAdjustment = TextParsingHelpers.netCalorieAdjustment(from: raw) {
            var result = PatternResult()
            result.intent = PatternSlot(value: "calorie_adjustment", confidence: nil, source: .pattern)
            result.meal_kcal = PatternSlot(value: calorieAdjustment, confidence: nil, source: .pattern)
            return result
        }
        
        if let currencyAdjustment = TextParsingHelpers.netCurrencyAdjustment(from: raw) {
            var result = PatternResult()
            let intentValue = currencyAdjustment.net >= 0 ? "income" : "expense"
            result.intent = PatternSlot(value: intentValue, confidence: nil, source: .pattern)
            result.amount = PatternSlot(value: abs(currencyAdjustment.net), confidence: nil, source: .pattern)
            result.currency = PatternSlot(value: currencyAdjustment.currency, confidence: nil, source: .pattern)
            return result
        }
        
        guard model.availability == .available else {
            var result = PatternResult()
            result.intent = PatternSlot(value: "none", confidence: nil, source: .foundationModel)
            return result
        }
        
        let intent = await IntentClassificationService.shared.classify(text: raw)
        
        switch intent {
        case "event":
            return await parseEvent(text: raw, originalText: raw)
        case "reminder":
            return await parseReminder(text: raw, originalText: raw)
        case "meal":
            return await parseMeal(text: raw, originalText: raw)
        case "expense":
            return await parseExpense(text: raw, originalText: raw)
        case "income":
            return await parseIncome(text: raw, originalText: raw)
        case "activity":
            return await parseActivity(text: raw, originalText: raw)
        case "work_start", "work_end":
            return await parseWorkSession(text: raw, originalText: raw, intent: intent)
        case "calorie_adjustment":
            return await parseCalorieAdjustment(text: raw)
        case "journal":
            return await parseJournal(text: raw, originalText: raw)
        default:
            var result = PatternResult()
            result.intent = PatternSlot(value: intent, confidence: nil, source: .foundationModel)
            return result
        }
    }
    
    private func parseEvent(text: String, originalText: String) async -> PatternResult {
        let translatedText = await TranslationService.shared.translateToEnglish(text)
        let parsed = await EventParserService.shared.parse(text: translatedText, originalText: originalText)
        let sanitized = NLPDateTimeSanitizer.sanitize(
            originalText: originalText,
            translatedText: translatedText,
            candidateDay: parsed.eventDay,
            candidateTime: parsed.eventTime
        )
        
        let dayForObject = sanitized.day ?? parsed.eventDay
        let timeForObject = sanitized.time ?? parsed.eventTime
        let originalObject = NLPObjectExtractor.extract(
            originalText: originalText,
            fallback: parsed.object,
            parsedDay: dayForObject,
            parsedTime: timeForObject
        )
        let refinedObject = await TitleRefinementService.shared.refineTitle(
            originalText: originalText,
            fallbackTitle: originalObject,
            intent: "event",
            dayLabel: sanitized.day,
            timeLabel: sanitized.time
        )
        
        var result = PatternResult()
        result.intent = PatternSlot(value: "event", confidence: nil, source: .foundationModel)
        result.object = PatternSlot(value: refinedObject, confidence: nil, source: .foundationModel)
        result.event_day = PatternSlot(value: sanitized.day, confidence: nil, source: .foundationModel)
        result.event_time = PatternSlot(value: sanitized.time, confidence: nil, source: .foundationModel)
        
        if let invalidDay = sanitized.invalidDayInput {
            result.event_day_error = PatternSlot(value: invalidDay, confidence: nil, source: .foundationModel)
        }
        if let invalidTime = sanitized.invalidTimeInput {
            result.event_time_error = PatternSlot(value: invalidTime, confidence: nil, source: .foundationModel)
        }
        
        return result
    }
    
    private func parseReminder(text: String, originalText: String) async -> PatternResult {
        let translatedText = await TranslationService.shared.translateToEnglish(text)
        let parsed = await ReminderParserService.shared.parse(text: translatedText, originalText: originalText)
        let sanitized = NLPDateTimeSanitizer.sanitize(
            originalText: originalText,
            translatedText: translatedText,
            candidateDay: parsed.reminderDay,
            candidateTime: parsed.reminderTime
        )
        
        let dayForObject = sanitized.day ?? parsed.reminderDay
        let timeForObject = sanitized.time ?? parsed.reminderTime
        let originalObject = NLPObjectExtractor.extract(
            originalText: originalText,
            fallback: parsed.object,
            parsedDay: dayForObject,
            parsedTime: timeForObject
        )
        let refinedObject = await TitleRefinementService.shared.refineTitle(
            originalText: originalText,
            fallbackTitle: originalObject,
            intent: "reminder",
            dayLabel: sanitized.day,
            timeLabel: sanitized.time
        )
        
        var result = PatternResult()
        result.intent = PatternSlot(value: "reminder", confidence: nil, source: .foundationModel)
        result.object = PatternSlot(value: refinedObject, confidence: nil, source: .foundationModel)
        result.reminder_day = PatternSlot(value: sanitized.day, confidence: nil, source: .foundationModel)
        result.reminder_time = PatternSlot(value: sanitized.time, confidence: nil, source: .foundationModel)
        
        if let invalidDay = sanitized.invalidDayInput {
            result.reminder_day_error = PatternSlot(value: invalidDay, confidence: nil, source: .foundationModel)
        }
        if let invalidTime = sanitized.invalidTimeInput {
            result.reminder_time_error = PatternSlot(value: invalidTime, confidence: nil, source: .foundationModel)
        }
        
        return result
    }
    
    private func parseMeal(text: String, originalText: String) async -> PatternResult {
        do {
            let parsed = try await MealParserService.shared.parse(text: originalText)
            
            var result = PatternResult()
            result.intent = PatternSlot(value: "meal", confidence: nil, source: .foundationModel)
            result.object = PatternSlot(value: parsed.object, confidence: nil, source: .foundationModel)
            result.meal_quantity = PatternSlot(value: parsed.mealQuantity, confidence: nil, source: .foundationModel)
            result.meal_kcal = PatternSlot(value: parsed.mealKcal, confidence: nil, source: .foundationModel)
            result.meal_is_menu = PatternSlot(value: parsed.isMenu, confidence: nil, source: .foundationModel)
            
            return result
        } catch is LanguageModelSession.GenerationError {
            var result = PatternResult()
            result.intent = PatternSlot(value: "none", confidence: nil, source: .foundationModel)
            return result
        } catch {
            
            var result = PatternResult()
            result.intent = PatternSlot(value: "none", confidence: nil, source: .foundationModel)
            return result
        }
    }
    
    private func parseExpense(text: String, originalText: String) async -> PatternResult {
        let parsed = await ExpenseParserService.shared.parse(text: text)
        
        var result = PatternResult()
        result.intent = PatternSlot(value: "expense", confidence: nil, source: .foundationModel)
        result.object = PatternSlot(value: parsed.object, confidence: nil, source: .foundationModel)
        result.currency = PatternSlot(value: parsed.currency, confidence: nil, source: .foundationModel)
        result.amount = PatternSlot(value: parsed.amount, confidence: nil, source: .foundationModel)
        
        return result
    }
    
    private func parseIncome(text: String, originalText: String) async -> PatternResult {
        let parsed = await IncomeParserService.shared.parse(text: text)
        
        var result = PatternResult()
        result.intent = PatternSlot(value: "income", confidence: nil, source: .foundationModel)
        result.object = PatternSlot(value: parsed.object, confidence: nil, source: .foundationModel)
        result.currency = PatternSlot(value: parsed.currency, confidence: nil, source: .foundationModel)
        result.amount = PatternSlot(value: parsed.amount, confidence: nil, source: .foundationModel)
        
        return result
    }
    
    private func parseActivity(text: String, originalText: String) async -> PatternResult {
        guard let parsed = await ActivityParserService.shared.parseActivity(from: text) else {
            return PatternResult()
        }
        
        var result = PatternResult()
        result.intent = PatternSlot(value: "activity", confidence: nil, source: .foundationModel)
        result.object = PatternSlot(value: parsed.activityType, confidence: nil, source: .foundationModel)
        result.duration = PatternSlot(value: parsed.duration, confidence: nil, source: .foundationModel)
        result.distance = PatternSlot(value: parsed.distance, confidence: nil, source: .foundationModel)
        // Store activity calories as negative value in meal_kcal (burned calories are negative)
        result.meal_kcal = PatternSlot(value: -parsed.caloriesBurned, confidence: nil, source: .foundationModel)
        
        return result
    }
    
    private func parseWorkSession(text: String, originalText: String, intent: String) async -> PatternResult {
        let object = await WorkSessionParserService.shared.parse(text: text)
        
        var result = PatternResult()
        result.intent = PatternSlot(value: intent, confidence: nil, source: .foundationModel)
        result.object = PatternSlot(value: object, confidence: nil, source: .foundationModel)
        
        return result
    }
    
    private func parseCalorieAdjustment(text: String) async -> PatternResult {
        let mealKcal = await CalorieAdjustmentParserService.shared.parse(text: text)
        
        var result = PatternResult()
        result.intent = PatternSlot(value: "calorie_adjustment", confidence: nil, source: .foundationModel)
        result.meal_kcal = PatternSlot(value: mealKcal, confidence: nil, source: .foundationModel)
        
        return result
    }
    
    func resolveVariable(from text: String) async -> PatternResult? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let normalized = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        let (variable, intentValue) = await MainActor.run { () -> (VariableStruct?, String) in
            let vars = VariableStore.getVariablesSnapshot()
            if let foundVar = vars.first(where: {
                $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased() == normalized
            }) {
                return (foundVar, foundVar.type.intent)
            }
            return (nil, "")
        }
        
        guard let variable = variable else {
            return nil
        }
        
        guard let numericValue = TextParsingHelpers.extractFirstNumber(from: variable.value) else {
            return nil
        }
        var result = PatternResult()
        result.intent = PatternSlot(value: intentValue, confidence: nil, source: .pattern)
        let slug = variable.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        result.object = PatternSlot(value: slug, confidence: nil, source: .pattern)
        
        switch variable.type {
        case .meal:
            result.meal_kcal = PatternSlot(value: numericValue, confidence: nil, source: .pattern)
        case .expense, .income:
            result.amount = PatternSlot(value: abs(numericValue), confidence: nil, source: .pattern)
            let currency = variable.currency ?? TextParsingHelpers.extractCurrency(from: variable.value)
            if let currency {
                result.currency = PatternSlot(value: currency, confidence: nil, source: .pattern)
            }
        }
        
        return result
    }
    
    private func parseJournal(text: String, originalText: String) async -> PatternResult {
        let moodEmojis = ["😢", "😕", "😐", "🙂", "😊"]
        var moodEmoji: String? = nil
        var journalText = originalText
        
        // Extract mood emoji from prefix
        for emoji in moodEmojis {
            if originalText.hasPrefix(emoji) {
                moodEmoji = emoji
                journalText = String(originalText.dropFirst(emoji.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        
        var result = PatternResult()
        result.intent = PatternSlot(value: "journal", confidence: nil, source: .foundationModel)
        
        if let emoji = moodEmoji {
            result.moodEmoji = PatternSlot(value: emoji, confidence: nil, source: .pattern)
        }
        
        if !journalText.isEmpty {
            result.object = PatternSlot(value: journalText, confidence: nil, source: .foundationModel)
        }
        
        return result
    }
        
    // MARK: - Text Validation
    
    private func isValidText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.count < 3 {
            return false
        }
        
        let chars = Array(trimmed.lowercased())
        if chars.count >= 3 {
            if chars.allSatisfy({ $0 == chars[0] }) {
                return false
            }
            
            if chars.count >= 6 {
                let half = chars.count / 2
                let firstHalf = Array(chars[0..<half])
                let secondHalf = Array(chars[half..<chars.count])
                if firstHalf == secondHalf {
                    return false
                }
            }
        }
        
        let alphanumeric = trimmed.filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
        let minAlphanumeric = Int(Double(trimmed.count) * 0.5)
        if alphanumeric.count < minAlphanumeric {
            return false
        }
        
        var maxRepeat = 1
        var currentRepeat = 1
        for i in 1..<chars.count {
            if chars[i] == chars[i-1] {
                currentRepeat += 1
                maxRepeat = max(maxRepeat, currentRepeat)
            } else {
                currentRepeat = 1
            }
        }
        if maxRepeat >= 4 {
            return false
        }
        
        return true
    }
}
