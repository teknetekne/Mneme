import Foundation

/// Handler for event and reminder intents
/// Handles time/day validation and subject extraction
final class EventHandler: IntentHandler {
    private let confidenceThreshold: Double = 0.6
    
    func handle(
        result: ParsedResult,
        text: String,
        lineId: UUID
    ) async -> [ParsingResultItem] {
        var items: [ParsingResultItem] = []
        
        // 1. Add intent
        if let intent = result.intent {
            items.append(ParsingResultItem(
                field: "Intent",
                value: NotepadFormatter.formatIntentForDisplay(intent.value),
                isValid: true,
                errorMessage: nil,
                confidence: intent.confidence
            ))
        }
        
        let isEvent = result.intent?.value == "event"
        
        // 2. Process reminder time
        if let reminderTime = result.reminderTime {
            items.append(processTime(time: reminderTime, fieldName: "Reminder Time"))
        } else if !isEvent && result.intent?.value == "reminder" && result.reminderDay != nil {
            // Default missing reminder time to 12:00 for dated reminders
            let noonTime = SlotPrediction(value: "12:00", confidence: 1.0, source: .foundationModel)
            items.append(processTime(time: noonTime, fieldName: "Reminder Time"))
        }
        
        // 3. Process reminder time error
        if let reminderTimeError = result.reminderTimeError {
            items.append(ParsingResultItem(
                field: "Reminder Time",
                value: reminderTimeError.value,
                isValid: false,
                errorMessage: "Invalid time",
                rawValue: reminderTimeError.value,
                confidence: reminderTimeError.confidence
            ))
        }
        
        // 4. Process event time
        if isEvent {
            if let eventTime = result.eventTime {
                items.append(processTime(time: eventTime, fieldName: "Event Time"))
            } else if result.eventDay != nil {
                // Default missing event time to 12:00 for dated events
                let noonTime = SlotPrediction(value: "12:00", confidence: 1.0, source: .foundationModel)
                items.append(processTime(time: noonTime, fieldName: "Event Time"))
            } else {
                // Both day and time missing for event
                items.append(ParsingResultItem(
                    field: "Event Time",
                    value: "Missing time",
                    isValid: false,
                    errorMessage: "Please specify a time",
                    confidence: 0.0
                ))
            }
        }
        
        // 5. Process event time error
        if let eventTimeError = result.eventTimeError {
            items.append(ParsingResultItem(
                field: "Event Time",
                value: eventTimeError.value,
                isValid: false,
                errorMessage: "Invalid time",
                rawValue: eventTimeError.value,
                confidence: eventTimeError.confidence
            ))
        }
        
        // 6. Process subject
        if let object = result.object, !object.value.isEmpty {
            let displayObject: String
            if object.value.contains("_+_") {
                let parts = object.value.components(separatedBy: "_+_")
                let capitalizedParts = parts.map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
                displayObject = capitalizedParts.joined(separator: " + ")
            } else {
                displayObject = object.value.replacingOccurrences(of: "_", with: " ").capitalized
            }
            items.append(ParsingResultItem(
                field: "Subject",
                value: displayObject,
                isValid: true,
                errorMessage: nil,
                rawValue: object.value,
                confidence: object.confidence
            ))
        }
        
        // 7. Process reminder day
        if let reminderDay = result.reminderDay, !reminderDay.value.isEmpty {
            items.append(processDay(day: reminderDay, fieldName: "Reminder Day"))
        } else if !isEvent && result.intent?.value == "reminder" {
            // Reminder without day - check if at least time exists
            if result.reminderTime == nil {
                items.append(ParsingResultItem(
                    field: "Reminder Day",
                    value: "Missing date or time",
                    isValid: false,
                    errorMessage: "Please specify a date or time",
                    confidence: 0.0
                ))
            }
        }
        
        // 8. Process reminder day error
        if let reminderDayError = result.reminderDayError {
            items.append(ParsingResultItem(
                field: "Reminder Day",
                value: reminderDayError.value,
                isValid: false,
                errorMessage: "Invalid date",
                rawValue: reminderDayError.value,
                confidence: reminderDayError.confidence
            ))
        }
        
        // 9. Process event day
        if let eventDay = result.eventDay, !eventDay.value.isEmpty {
            items.append(processDay(day: eventDay, fieldName: "Event Day"))
        } else if isEvent {
            // Event without a valid day - mark as invalid
            items.append(ParsingResultItem(
                field: "Event Day",
                value: "Missing or invalid date",
                isValid: false,
                errorMessage: "Please specify a valid date",
                confidence: 0.0
            ))
        }
        
        // 10. Process event day error
        if let eventDayError = result.eventDayError {
            items.append(ParsingResultItem(
                field: "Event Day",
                value: eventDayError.value,
                isValid: false,
                errorMessage: "Invalid date",
                rawValue: eventDayError.value,
                confidence: eventDayError.confidence
            ))
        }
        
        return items
    }
    
    // MARK: - Private Helpers
    
    private func processTime(
        time: SlotPrediction<String>,
        fieldName: String
    ) -> ParsingResultItem {
        let confidence = time.confidence
        let isConfident = !shouldMarkAsInvalid(confidence: confidence)
        let isValid = NotepadValidator.isValidTime(time.value) && isConfident
        let displayTime = NotepadFormatter.formatTimeForDisplay(time.value)
        
        return ParsingResultItem(
            field: fieldName,
            value: displayTime.isEmpty ? time.value : displayTime,
            isValid: isValid,
            errorMessage: isValid ? nil : (isConfident ? "Invalid time format" : "Low confidence prediction"),
            rawValue: time.value,
            confidence: confidence
        )
    }
    
    private func processDay(
        day: SlotPrediction<String>,
        fieldName: String
    ) -> ParsingResultItem {
        let confidence = day.confidence
        let isConfident = !shouldMarkAsInvalid(confidence: confidence)
        let isValid = NotepadValidator.isValidDate(day.value) && isConfident
        let displayDay = NotepadFormatter.formatDayForDisplay(day.value)
        
        return ParsingResultItem(
            field: fieldName,
            value: displayDay.isEmpty ? day.value : displayDay,
            isValid: isValid,
            errorMessage: isValid ? nil : (isConfident ? "Invalid date format" : "Low confidence prediction"),
            rawValue: day.value,
            confidence: confidence
        )
    }
    
    private func shouldMarkAsInvalid(confidence: Double?) -> Bool {
        guard let confidence = confidence else { return false }
        return confidence < confidenceThreshold
    }
}
