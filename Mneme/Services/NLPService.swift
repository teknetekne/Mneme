import Foundation

struct SlotPrediction<T> {
    let value: T
    let confidence: Double?
    let source: FusionSource
}

nonisolated struct ParsedResult {
    var intent: SlotPrediction<String>?
    var object: SlotPrediction<String>?
    var reminderTime: SlotPrediction<String>?
    var reminderDay: SlotPrediction<String>?
    var eventTime: SlotPrediction<String>?
    var eventDay: SlotPrediction<String>?
    var reminderDayError: SlotPrediction<String>?
    var reminderTimeError: SlotPrediction<String>?
    var eventDayError: SlotPrediction<String>?
    var eventTimeError: SlotPrediction<String>?
    var currency: SlotPrediction<String>?
    var amount: SlotPrediction<Double>?
    var duration: SlotPrediction<Double>?
    var distance: SlotPrediction<Double>?
    var mealQuantity: SlotPrediction<String>?
    var mealKcal: SlotPrediction<Double>?
    var mealIsMenu: SlotPrediction<Bool>?
    var location: SlotPrediction<String>?
    var url: SlotPrediction<String>?
    var moodEmoji: SlotPrediction<String>?

    var time: SlotPrediction<String>? { reminderTime ?? eventTime }
    var day: SlotPrediction<String>? { reminderDay ?? eventDay }
}

protocol NLPServicing {
    func parse(text: String) async -> ParsedResult
}

nonisolated final class NLPService: NLPServicing {
    nonisolated(unsafe) static let shared = NLPService()
    
    nonisolated init() {}
    
    nonisolated func parse(text: String) async -> ParsedResult {
        // Use Foundation Models for parsing
        let foundationResult = await FoundationModelsNLP.shared.parse(text: text)

        var result = ParsedResult()
        result.intent = convert(foundationResult.intent)
        result.object = convert(foundationResult.object)
        result.reminderTime = convert(foundationResult.reminder_time)
        result.reminderDay = convert(foundationResult.reminder_day)
        result.eventTime = convert(foundationResult.event_time)
        result.eventDay = convert(foundationResult.event_day)
        result.currency = convert(foundationResult.currency)
        result.reminderDayError = convert(foundationResult.reminder_day_error)
        result.reminderTimeError = convert(foundationResult.reminder_time_error)
        result.eventDayError = convert(foundationResult.event_day_error)
        result.eventTimeError = convert(foundationResult.event_time_error)
        result.amount = convert(foundationResult.amount)
        result.duration = convert(foundationResult.duration)
        result.distance = convert(foundationResult.distance)
        result.mealQuantity = convert(foundationResult.meal_quantity)
        result.mealKcal = convert(foundationResult.meal_kcal)
        result.mealIsMenu = convert(foundationResult.meal_is_menu)
        result.location = convert(foundationResult.location)
        result.url = convert(foundationResult.url)
        result.moodEmoji = convert(foundationResult.moodEmoji)
        return result
    }

    private nonisolated func convert<T>(_ slot: PatternSlot<T>) -> SlotPrediction<T>? {
        guard let value = slot.value, let source = slot.source else { return nil }
        return SlotPrediction(value: value, confidence: slot.confidence, source: source)
    }
}
