import Foundation

// MARK: - NLP Types

enum FusionSource: String, Sendable {
    case pattern
    case foundationModel
}

nonisolated struct PatternSlot<T> {
    var value: T?
    var confidence: Double?
    var source: FusionSource?

    nonisolated init(value: T? = nil, confidence: Double? = nil, source: FusionSource? = nil) {
        self.value = value
        self.confidence = confidence
        self.source = source
    }
}

nonisolated struct PatternResult {
    var intent = PatternSlot<String>()
    var object = PatternSlot<String>()
    var reminder_day = PatternSlot<String>()
    var reminder_time = PatternSlot<String>()
    var event_day = PatternSlot<String>()
    var event_time = PatternSlot<String>()
    var reminder_day_error = PatternSlot<String>()
    var reminder_time_error = PatternSlot<String>()
    var event_day_error = PatternSlot<String>()
    var event_time_error = PatternSlot<String>()
    var currency = PatternSlot<String>()
    var amount = PatternSlot<Double>()
    var duration = PatternSlot<Double>()
    var distance = PatternSlot<Double>()
    var meal_quantity = PatternSlot<String>()
    var meal_kcal = PatternSlot<Double>()
    var meal_is_menu = PatternSlot<Bool>()
    var location = PatternSlot<String>()
    var url = PatternSlot<String>()
    var moodEmoji = PatternSlot<String>()
}

