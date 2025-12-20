import Foundation

/// Handler for expense and income intents
/// Handles amount validation, currency detection, variable lookup, and async currency conversion
final class ExpenseHandler: IntentHandler {
    private let confidenceThreshold: Double = 0.6
    private let currencyService = CurrencyService.shared
    private let currencySettingsStore = CurrencySettingsStore.shared
    private let variableHandler = VariableHandler.shared
    
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
        
        // 2. Add subject
        if let object = result.object, !object.value.isEmpty {
            let displayObject = object.value.replacingOccurrences(of: "_", with: " ").capitalized
            items.append(ParsingResultItem(
                field: "Subject",
                value: displayObject,
                isValid: true,
                errorMessage: nil,
                rawValue: object.value,
                confidence: object.confidence
            ))
        }
        
        // 3. Add currency
        if let currency = result.currency, !currency.value.isEmpty {
            let confidence = currency.confidence
            let isConfident = !shouldMarkAsInvalid(confidence: confidence)
            let isValid = NotepadValidator.isValidCurrency(currency.value) && isConfident
            items.append(ParsingResultItem(
                field: "Currency",
                value: currency.value,
                isValid: isValid,
                errorMessage: isValid ? nil : (isConfident ? "Invalid currency code" : "Low confidence prediction"),
                confidence: confidence
            ))
        }
        
        // 4. Check for variable-based amount (e.g., "salary", "rent")
        let intentValue = result.intent?.value
        if let intent = intentValue, (intent == "income" || intent == "expense"),
           let objectName = result.object?.value.replacingOccurrences(of: "_", with: " ") {
            let baseCurrency = await MainActor.run { currencySettingsStore.baseCurrency }
            if let amountItem = variableHandler.handleExpenseIncomeVariable(
                objectName: objectName,
                intent: intent,
                currency: result.currency?.value,
                baseCurrency: baseCurrency
            ) {
                items.append(amountItem)
                return items
            }
        }
        
        // 5. Process amount with conversion (if no variable found)
        if let amount = result.amount {
            let amountResult = await processAmount(
                amount: amount,
                intent: intentValue,
                currency: result.currency?.value
            )
            items.append(amountResult)
        }
        
        return items
    }
    
    // MARK: - Private Helpers
    
    private func processAmount(
        amount: SlotPrediction<Double>,
        intent: String?,
        currency: String?
    ) async -> ParsingResultItem {
        let confidence = amount.confidence
        let isConfident = !shouldMarkAsInvalid(confidence: confidence)
        let isValid = NotepadValidator.isValidAmount(amount.value) && isConfident
        
        // Determine sign based on intent
        let sign: String
        if intent == "expense" {
            sign = "-"
        } else if intent == "income" {
            sign = "+"
        } else {
            sign = amount.value >= 0 ? "+" : "-"
        }
        
        // Check if currency conversion is needed
        guard let currency = currency, !currency.isEmpty else {
            // No currency, just format amount
            let displayAmount = intent == "expense" ? -abs(amount.value) : (intent == "income" ? abs(amount.value) : amount.value)
            return ParsingResultItem(
                field: "Amount",
                value: String(format: "%@%.2f", displayAmount >= 0 ? "+" : "-", abs(displayAmount)),
                isValid: isValid,
                errorMessage: isValid ? nil : (isConfident ? "Amount cannot be zero" : "Low confidence prediction"),
                confidence: confidence
            )
        }
        
        // Check if conversion needed
        let baseCurrency = await MainActor.run { currencySettingsStore.baseCurrency }
        let needsConversion = currency.uppercased() != baseCurrency.uppercased()
        
        if !needsConversion {
            // Same currency, no conversion needed
            let originalAmountValue = String(format: "%@%.2f %@", sign, abs(amount.value), currency)
            return ParsingResultItem(
                field: "Amount",
                value: originalAmountValue,
                isValid: isValid,
                errorMessage: isValid ? nil : (isConfident ? "Amount cannot be zero" : "Low confidence prediction"),
                confidence: confidence
            )
        }
        
        // Conversion needed - perform async conversion
        if let convertedAmount = await currencyService.convertAmount(
            abs(amount.value),
            from: currency,
            to: baseCurrency
        ) {
            // Conversion successful
            let convertedSign = intent == "expense" ? "-" : "+"
            let convertedValue = String(format: "%@%.2f %@", convertedSign, convertedAmount, baseCurrency)
            let originalValue = String(format: "%@%.2f %@", sign, abs(amount.value), currency)
            
            return ParsingResultItem(
                field: "Amount",
                value: convertedValue,
                isValid: true,
                errorMessage: nil,
                rawValue: originalValue,
                confidence: confidence
            )
        } else {
            // Conversion failed
            let originalAmountValue = String(format: "%@%.2f %@", sign, abs(amount.value), currency)
            return ParsingResultItem(
                field: "Amount",
                value: originalAmountValue,
                isValid: false,
                errorMessage: "Failed to convert currency. Please check your internet connection.",
                rawValue: originalAmountValue,
                confidence: confidence
            )
        }
    }
    
    private func shouldMarkAsInvalid(confidence: Double?) -> Bool {
        guard let confidence = confidence else { return false }
        return confidence < confidenceThreshold
    }
}
