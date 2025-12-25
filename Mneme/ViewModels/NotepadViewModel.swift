import Foundation
import SwiftUI
import Combine
import EventKit

// MARK: - Notepad ViewModel (Refactored)

/// Refactored NotepadViewModel using composition with managers
/// Responsibility: Thin coordinator layer that delegates to specialized managers
/// Total lines: ~417 (vs 1,592 in original) - 74% reduction
@MainActor
final class NotepadViewModel: ObservableObject {
    
    // MARK: - Managers (Composition Pattern)
    
    @ObservedObject var lineStore: LineStore  // Dictionary-based, safe for binding (public for View)
    private let lineManager: LineManager  // Internal only
    private let tagManager: TagManager
    private let eventKitManager: EventKitManager
    @ObservedObject var workSessionManager: WorkSessionManager  // Public for binding
    @ObservedObject var locationManager: LocationManager
    
    // MARK: - Services
    
    private let nlpService = NLPService.shared
    private let currencyService = CurrencyService.shared
    @ObservedObject var currencySettingsStore = CurrencySettingsStore.shared
    private let notepadEntryStore = NotepadEntryStore.shared
    private let variableStore = VariableStore.shared
    
    // MARK: - Published Properties (UI State)
    
    // Lines now managed by lineStore (dictionary-based)
    var lines: [LineViewModel] { lineStore.lines }  // Computed property
    @Published var lineParsingResults: [UUID: [ParsingResultItem]] = [:]  // Parsing results for each line
    @Published var manualOverrides: [UUID: LineOverride] = [:]
    
    struct LineOverride {
        var subject: String?
        var date: Date?
    }
    
    @Published var snackbarMessage: String = ""
    @Published var snackbarTitle: String = ""
    @Published var showSnackbar: Bool = false
    @Published var snackbarType: SnackbarType = .success
    
    enum SnackbarType {
        case success
        case error
    }
    
    // MARK: - Parsing (from old code)
    
    private var debounceTasks: [UUID: Task<Void, Never>] = [:]
    
    private let confidenceThreshold: Double = 0.6
    private let typingThrottleNanoseconds: UInt64 = 300_000_000
    private let minParseLength = 3
    
    private func shouldMarkAsInvalid(confidence: Double?) -> Bool {
        guard let confidence = confidence else { return false }
        return confidence < confidenceThreshold
    }
    
    // MARK: - Debounced Parsing
    
    func scheduleDebouncedParse(for id: UUID) {
        debounceTasks[id]?.cancel()
        
        debounceTasks[id] = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 800_000_000)
                
                lineStore.updateStatus(for: id, status: .loading)
                
                guard let currentText = lineStore.linesById[id]?.text else {
                    return
                }
                
                await parseLine(id: id, text: currentText)
            } catch {
            }
        }
    }
    
    // MARK: - Parse Line (Handler Pattern)
    
    private func parseLine(id: UUID, text: String) async {
        guard lineStore.linesById[id] != nil,
              lineStore.linesById[id]?.text.trimmingCharacters(in: .whitespacesAndNewlines) == text else {
            return
        }
        
        // Check for variable arithmetic FIRST (+salary-rent, +salary, etc.)
        // This prevents NLP from making up values for variable names
        if let expressionResult = VariableHandler.shared.evaluateExpression(text, baseCurrency: CurrencySettingsStore.shared.baseCurrency) {
            var items: [ParsingResultItem] = []
            
            // Determine intent based on result field
            let intent: String
            if expressionResult.field == "Calories" {
                intent = "meal"
            } else {
                // For money: check sign in the result value
                intent = expressionResult.value.contains("-") ? "expense" : "income"
            }
            
            items.append(ParsingResultItem(
                field: "Intent",
                value: intent,  // Store raw value: "income", "expense", "meal"
                isValid: true,
                errorMessage: nil,
                confidence: 1.0
            ))
            
            // Extract subject from text (remove operators)
            let subject = text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "+", with: "")
                .replacingOccurrences(of: "-", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .capitalized
            
            if !subject.isEmpty {
                items.append(ParsingResultItem(
                    field: "Subject",
                    value: subject,
                    isValid: true,
                    errorMessage: nil,
                    rawValue: subject.lowercased(),
                    confidence: 1.0
                ))
            }
            
            // Add the amount/calories result
            items.append(expressionResult)
            
            lineStore.updateStatus(for: id, status: .success)
            lineParsingResults[id] = items
            return
        }
        
        // If not a variable expression, parse with NLP
        let result = await Task.detached(priority: .userInitiated) { [nlpService] in
            await nlpService.parse(text: text)
        }.value
        
        let intentValue = result.intent?.value
        
        let results: [ParsingResultItem] = await Task.detached(priority: .userInitiated) {
            guard let intentValue = intentValue, intentValue != "none" else {
                return []
            }
            
            let handler = await HandlerFactory.handler(for: intentValue)
            let handlerResults = await handler.handle(result: result, text: text, lineId: id)
            return handlerResults
        }.value
        
        guard lineStore.linesById[id] != nil,
              lineStore.linesById[id]?.text.trimmingCharacters(in: .whitespacesAndNewlines) == text else {
            return
        }
        
        guard !results.isEmpty else {
            lineStore.updateStatus(for: id, status: .error)
            lineParsingResults.removeValue(forKey: id)
            return
        }
        
        // If any result is invalid, mark the line as error (still show results for context)
        let hasInvalid = results.contains { !$0.isValid }
        lineStore.updateStatus(for: id, status: hasInvalid ? .error : .success)
        lineParsingResults[id] = results
    }
    
    // MARK: - Initialization
    
    init(
        lineStore: LineStore? = nil,
        lineManager: LineManager? = nil,
        tagManager: TagManager? = nil,
        workSessionManager: WorkSessionManager? = nil
    ) {
        self.lineStore = lineStore ?? LineStore()
        let lm = lineManager ?? LineManager()
        self.lineManager = lm
        self.tagManager = tagManager ?? TagManager()
        self.workSessionManager = workSessionManager ?? WorkSessionManager()
        
        // Initialize EventKitManager with TagManager
        self.eventKitManager = EventKitManager(tagManager: self.tagManager)
        
        // Initialize LocationManager
        self.locationManager = LocationManager()
    }
    
    // MARK: - Lines Management
    
    func addLineAndFocus() -> UUID {
        return lineStore.addLine()
    }
    
    func handleBackspaceOnEmptyLine(for id: UUID) -> UUID? {
        if let prevId = lineStore.handleBackspaceOnEmptyLine(for: id) {
            lineParsingResults.removeValue(forKey: id)
            return prevId
        }
        return nil
    }
    
    func handleNewline(for id: UUID) -> UUID? {
        guard let result = lineStore.handleNewline(for: id) else {
            return addLineAndFocus()
        }
        
        if let line = lineStore.linesById[id],
           line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lineParsingResults.removeValue(forKey: id)
        }
        
        return result.focus
    }
    
    func handleTextChange(for id: UUID, oldValue: String, newValue: String) {
        let newTrimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if newTrimmed.isEmpty {
            debounceTasks[id]?.cancel()
            debounceTasks.removeValue(forKey: id)
            Task { @MainActor in
                lineStore.updateStatus(for: id, status: .idle)
                lineParsingResults.removeValue(forKey: id)
            }
            return
        }

        if newTrimmed.count < minParseLength {
            debounceTasks[id]?.cancel()
            debounceTasks.removeValue(forKey: id)
            Task { @MainActor in
                lineStore.updateStatus(for: id, status: .idle)
                lineParsingResults.removeValue(forKey: id)
            }
            return
        }
        
        debounceTasks[id]?.cancel()
        
        // UX Fix: Immediately stop loading indicator if user resumes typing
        if lineStore.linesById[id]?.status == .loading {
            lineStore.updateStatus(for: id, status: .idle)
        }
        
        debounceTasks[id] = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: typingThrottleNanoseconds)
            } catch {
                return
            }
            self.scheduleDebouncedParse(for: id)
        }
    }
    
    func resetLines() {
        lineStore.resetToInitialState()
        lineParsingResults.removeAll()
        manualOverrides.removeAll()
        locationManager.clearAllData()
    }
    
    func updateLineText(for id: UUID, newText: String) {
        lineStore.updateText(for: id, newText: newText)
    }
    
    func validateExistingLines() {
        // Snapshot the lines to ensure thread safety and stability
        let snapshot = lines.compactMap { line -> (UUID, String)? in
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : (line.id, line.text)
        }
        
        Task {
            // Show loading state immediately for better UX
            for (id, _) in snapshot {
                lineStore.updateStatus(for: id, status: .loading)
            }
            
            // Re-validate all lines sequentially
            for (id, text) in snapshot {
                await parseLine(id: id, text: text)
            }
        }
    }
    
    // MARK: - Parsing Results
    
    var showParsingResults: Bool {
        !lineParsingResults.isEmpty
    }
    
    func getResults(for lineId: UUID) -> [ParsingResultItem] {
        lineParsingResults[lineId] ?? []
    }
    
    // MARK: - Validation
    
    var allLinesParsedSuccessfully: Bool {
        let nonEmptyLines = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonEmptyLines.isEmpty else { return false }
        
        let allSuccess = nonEmptyLines.allSatisfy { $0.status == .idle || $0.status == .success }
        guard allSuccess else { return false }
        
        let allValid = nonEmptyLines.allSatisfy { line in
            guard let results = lineParsingResults[line.id] else { return false }
            return results.allSatisfy { $0.isValid }
        }
        
        return allValid
    }
    
    // MARK: - Reminder/Event Detection
    
    var reminderEvents: [(id: UUID, type: String, subject: String, displayName: String, day: String?, time: String?, rawDay: String?, rawTime: String?)] {
        var events: [(id: UUID, type: String, subject: String, displayName: String, day: String?, time: String?, rawDay: String?, rawTime: String?)] = []
        
        for line in lines where line.status != .error {
            guard let results = lineParsingResults[line.id] else { continue }
            guard let intentItem = results.first(where: { $0.field == "Intent" }) else {
                continue
            }
            
            let normalizedIntent = NotepadFormatter.normalizeIntentForCheck(intentItem.value)
            
            // Determine if it's an event or reminder
            let isReminder = normalizedIntent == "reminder"
            let isEvent = normalizedIntent == "event"
            
            guard isReminder || isEvent else { continue }
            
            let hasReminderTime = results.contains { $0.field == "Reminder Time" && $0.isValid }
            let fallbackReminderTime = results.contains { $0.field == "Event Time" && $0.isValid }
            let hasEventTime = results.contains { $0.field == "Event Time" && $0.isValid }
            let fallbackEventTime = results.contains { $0.field == "Reminder Time" && $0.isValid }
            
            if isReminder && (hasReminderTime || fallbackReminderTime) {
                let (subject, displayName) = overriddenSubject(for: line.id, from: results, fallbackLabel: "Reminder")
                let (day, time, rawDay, rawTime) = overriddenDateTime(for: line.id, from: results, fields: ["Day": ["Reminder Day", "Event Day"], "Time": ["Reminder Time", "Event Time"]])
                
                events.append((id: line.id, type: "reminder", subject: subject, displayName: displayName, day: day, time: time, rawDay: rawDay, rawTime: rawTime))
            } else if isEvent && (hasEventTime || fallbackEventTime) {
                let (subject, displayName) = overriddenSubject(for: line.id, from: results, fallbackLabel: "Event")
                let (day, time, rawDay, rawTime) = overriddenDateTime(for: line.id, from: results, fields: ["Day": ["Event Day", "Reminder Day"], "Time": ["Event Time", "Reminder Time"]])
                
                var finalTime = time
                if finalTime == nil && day != nil {
                    finalTime = "12:00"
                }
                
                events.append((id: line.id, type: "event", subject: subject, displayName: displayName, day: day, time: finalTime, rawDay: rawDay, rawTime: rawTime))
            }
        }
        
        return events
    }

    private func overriddenSubject(for id: UUID, from results: [ParsingResultItem], fallbackLabel: String) -> (String, String) {
        if let manual = manualOverrides[id]?.subject {
            return (manual, manual)
        }
        return formattedSubject(from: results, fallbackLabel: fallbackLabel)
    }

    private func overriddenDateTime(for id: UUID, from results: [ParsingResultItem], fields: [String: [String]]) -> (day: String?, time: String?, rawDay: String?, rawTime: String?) {
        if let manualDate = manualOverrides[id]?.date {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            let isoDay = df.string(from: manualDate)
            df.dateFormat = "HH:mm"
            let isoTime = df.string(from: manualDate)
            
            let displayDay = NotepadFormatter.formatDayForDisplay(isoDay)
            let displayTime = NotepadFormatter.formatTimeForDisplay(isoTime)
            
            return (displayDay, displayTime, isoDay, isoTime)
        }
        
        let dayKeys = fields["Day"] ?? []
        let timeKeys = fields["Time"] ?? []
        
        let day = firstValidValue(in: results, fields: dayKeys)
        let time = firstValidValue(in: results, fields: timeKeys)
        let rawDay = firstRawValue(in: results, fields: dayKeys)
        let rawTime = firstRawValue(in: results, fields: timeKeys)
        
        return (day, time, rawDay, rawTime)
    }

    private func firstRawValue(in results: [ParsingResultItem], fields: [String]) -> String? {
        for field in fields {
            if let item = results.first(where: { $0.field == field && $0.isValid }) {
                return item.value
            }
        }
        return nil
    }
    
    var hasReminderOrEvent: Bool {
        !reminderEvents.isEmpty
    }
    
    private func formattedSubject(from results: [ParsingResultItem], fallbackLabel: String) -> (String, String) {
        if let subjectItem = results.first(where: { $0.field == "Subject" && $0.isValid }) {
            let raw = subjectItem.rawValue ?? subjectItem.value
            let formatted = raw.isEmpty ? fallbackLabel : formatTitle(raw)
            return (formatted, formatted)
        }
        return ("", fallbackLabel)
    }
    
    private func firstValidValue(in results: [ParsingResultItem], fields: [String]) -> String? {
        for field in fields {
            if let item = results.first(where: { $0.field == field && $0.isValid }) {
                if field.contains("Day") {
                    let formatted = NotepadFormatter.formatDayForDisplay(item.value)
                    return formatted.isEmpty ? item.value : formatted
                } else if field.contains("Time") {
                    let formatted = NotepadFormatter.formatTimeForDisplay(item.value)
                    return formatted.isEmpty ? item.value : formatted
                } else {
                    return item.value
                }
            }
        }
        return nil
    }
    
    // MARK: - Tag Operations (Delegated to TagManager)
    
    func getTagObjects(for lineId: UUID) -> [Tag] {
        tagManager.getTags(for: lineId)
    }
    
    func getUnaddedTags(for lineId: UUID) -> [Tag] {
        tagManager.getUnaddedTags(for: lineId)
    }
    
    func addTag(lineId: UUID, tag: String, colorName: String? = nil) {
        Task {
            do {
                try await tagManager.addTag(to: lineId, tagName: tag, colorName: colorName)
                await MainActor.run {
                    objectWillChange.send()
                }
            } catch {
                showError("Failed to add tag: \(error.localizedDescription)")
            }
        }
    }
    
    func removeTag(lineId: UUID, tag: String) {
        Task {
            let tags = tagManager.getTags(for: lineId)
            if let tagObj = tags.first(where: { $0.name == tag }) {
                do {
                    try await tagManager.removeTag(from: lineId, tag: tagObj)
                    await MainActor.run {
                        objectWillChange.send()
                    }
                } catch {
                    showError("Failed to remove tag: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func getTagColor(for tag: String) -> Color {
        let allTags = tagManager.getAllTags()
        if let tagObj = allTags.first(where: { $0.name == tag }) {
            return tagObj.color
        }
        return TagStore.color(from: TagStore.colorForTag(tag))
    }
    
    func updateTagInDatabase(oldName: String, newName: String, colorName: String? = nil) {
        Task {
            let allTags = tagManager.getAllTags()
            if let tagObj = allTags.first(where: { $0.name == oldName }) {
                do {
                    try await tagManager.updateTag(tagObj, newName: newName, newColorName: colorName ?? tagObj.colorName)
                    await MainActor.run {
                        objectWillChange.send()
                    }
                } catch {
                    showError("Failed to update tag: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func deleteTag(_ tagName: String) {
        Task {
            let allTags = tagManager.getAllTags()
            if let tagObj = allTags.first(where: { $0.name == tagName }) {
                do {
                    try await tagManager.deleteTag(tagObj)
                    await MainActor.run {
                        objectWillChange.send()
                    }
                } catch {
                    showError("Failed to delete tag: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Location Operations (Delegated to LocationManager)
    
    func setLocation(for lineId: UUID, name: String) {
        locationManager.setLocation(for: lineId, locationName: name)
    }
    
    func setLocation(for lineId: UUID, locationName: String) {
        locationManager.setLocation(for: lineId, locationName: locationName)
    }
    
    func getLocation(for lineId: UUID) -> String? {
        locationManager.getLocation(for: lineId)
    }
    
    func removeLocation(from lineId: UUID) {
        locationManager.removeLocation(from: lineId)
        objectWillChange.send()
    }
    
    func setURL(for lineId: UUID, url: URL) {
        locationManager.setURL(for: lineId, url: url)
    }
    
    func getURL(for lineId: UUID) -> URL? {
        locationManager.getURL(for: lineId)
    }
    
    func removeURL(from lineId: UUID) {
        locationManager.removeURL(from: lineId)
    }
    
    func detectAndStoreURL(in text: String, for lineId: UUID) {
        locationManager.detectAndStoreURL(in: text, for: lineId)
        if let url = locationManager.getURL(for: lineId) {
            setURL(for: lineId, url: url)
        }
    }
    
    // MARK: - Work Session Operations (Delegated to WorkSessionManager)
    
    func confirmWorkStartReplacement() {
        Task {
            do {
                try await workSessionManager.confirmWorkStartReplacement()
            } catch {
                showError("Failed to start work session: \(error.localizedDescription)")
            }
        }
    }
    
    func cancelWorkStartReplacement() {
        workSessionManager.cancelWorkStartReplacement()
    }
    
    // MARK: - EventKit Operations (Delegated to EventKitManager)
    
    func createReminder(for lineId: UUID) async throws {
        let results = lineParsingResults[lineId] ?? []
        guard let line = lines.first(where: { $0.id == lineId }) else { return }
        
        // Convert to ParsedResult (simplified)
        let parsedResult = convertToParseResult(from: results)
        let location = locationManager.getLocation(for: lineId)
        let url = locationManager.getURL(for: lineId)
        
        try await eventKitManager.createReminder(
            from: parsedResult,
            originalText: line.text,
            lineId: lineId,
            location: location,
            url: url
        )
        
        showSuccess("Reminder created successfully")
    }
    
    func createEvent(for lineId: UUID) async throws {
        let results = lineParsingResults[lineId] ?? []
        guard let line = lines.first(where: { $0.id == lineId }) else { return }
        
        // Convert to ParsedResult (simplified)
        let parsedResult = convertToParseResult(from: results)
        let location = locationManager.getLocation(for: lineId)
        let url = locationManager.getURL(for: lineId)
        
        try await eventKitManager.createEvent(
            from: parsedResult,
            originalText: line.text,
            lineId: lineId,
            location: location,
            url: url
        )
        
        showSuccess("Event created successfully")
    }
    
    // MARK: - Helper Methods
    
    /// Format title: "aile_yemeği" -> "Aile Yemeği"
    func formatTitle(_ title: String) -> String {
        let withSpaces = title.replacingOccurrences(of: "_", with: " ")
        let words = withSpaces.split(separator: " ")
        let capitalizedWords = words.map { word -> String in
            guard !word.isEmpty else { return String(word) }
            let firstChar = String(word.prefix(1)).localizedUppercase
            let restChars = String(word.dropFirst())
            return firstChar + restChars
        }
        
        let suffixMap: [String: String] = [
            "yla": "'yla", "yle": "'yle", "ya": "'ya", "ye": "'ye",
            "la": "'la", "le": "'le", "na": "'na", "ne": "'ne"
        ]
        
        var merged: [String] = []
        for word in capitalizedWords {
            let lower = word.lowercased()
            if let suffix = suffixMap[lower], let last = merged.popLast() {
                merged.append(last + suffix)
            } else {
                merged.append(word)
            }
        }
        
        return merged.joined(separator: " ")
    }
    
    /// Convert ParsingResultItem array to ParsedResult
    // MARK: - Text Reconstruction
    

    
    func updateLineFromEdit(lineId: UUID, title: String, date: Date, isReminder: Bool) {
        manualOverrides[lineId] = LineOverride(subject: title, date: date)
    }
    
    private func convertToParseResult(from items: [ParsingResultItem], for lineId: UUID? = nil) -> ParsedResult {
        var result = ParsedResult()
        
        let overrides = lineId.flatMap { manualOverrides[$0] }
        
        for item in items {
            switch item.field {
            case "Intent":
                let normalizedIntent = NotepadFormatter.normalizeIntentForCheck(item.value)
                result.intent = SlotPrediction(value: normalizedIntent, confidence: item.confidence ?? 1.0, source: .foundationModel)
            case "Subject":
                result.object = SlotPrediction(value: item.value, confidence: item.confidence ?? 1.0, source: .foundationModel)
            case "Reminder Day":
                result.reminderDay = SlotPrediction(value: item.value, confidence: item.confidence ?? 1.0, source: .foundationModel)
            case "Reminder Time":
                result.reminderTime = SlotPrediction(value: item.value, confidence: item.confidence ?? 1.0, source: .foundationModel)
            case "Event Day":
                result.eventDay = SlotPrediction(value: item.value, confidence: item.confidence ?? 1.0, source: .foundationModel)
            case "Event Time":
                result.eventTime = SlotPrediction(value: item.value, confidence: item.confidence ?? 1.0, source: .foundationModel)
            case "Amount":
                if let amountValue = TextParsingHelpers.extractFirstNumber(from: item.value) {
                    result.amount = SlotPrediction(value: amountValue, confidence: item.confidence ?? 1.0, source: .foundationModel)
                }
                if let currencyValue = TextParsingHelpers.extractCurrency(from: item.value) {
                    result.currency = SlotPrediction(value: currencyValue, confidence: item.confidence ?? 1.0, source: .foundationModel)
                }
            case "Calories", "Calories Burned":
                if let calorieValue = TextParsingHelpers.extractFirstNumber(from: item.value) {
                    result.mealKcal = SlotPrediction(value: calorieValue, confidence: item.confidence ?? 1.0, source: .foundationModel)
                }
            case "Currency":
                result.currency = SlotPrediction(value: item.value, confidence: item.confidence ?? 1.0, source: .foundationModel)
            case "Location":
                result.location = SlotPrediction(value: item.value, confidence: item.confidence ?? 1.0, source: .foundationModel)
            case "URL":
                result.url = SlotPrediction(value: item.value, confidence: item.confidence ?? 1.0, source: .foundationModel)
            case "Mood":
                result.moodEmoji = SlotPrediction(value: item.value, confidence: item.confidence ?? 1.0, source: .foundationModel)
            case "Duration":
                if let durationValue = TextParsingHelpers.extractFirstNumber(from: item.value) {
                    result.duration = SlotPrediction(value: durationValue, confidence: item.confidence ?? 1.0, source: .foundationModel)
                }
            case "Distance":
                if let distanceValue = TextParsingHelpers.extractFirstNumber(from: item.value) {
                    result.distance = SlotPrediction(value: distanceValue, confidence: item.confidence ?? 1.0, source: .foundationModel)
                }
            default:
                break
            }
        }
        
        // Apply overrides
        if let manualSubject = overrides?.subject {
            result.object = SlotPrediction(value: manualSubject, confidence: 1.0, source: .manual)
        }
        
        if let manualDate = overrides?.date {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            let dayString = df.string(from: manualDate)
            df.dateFormat = "HH:mm"
            let timeString = df.string(from: manualDate)
            
            // Apply to both reminder and event fields to be safe
            result.reminderDay = SlotPrediction(value: dayString, confidence: 1.0, source: .manual)
            result.reminderTime = SlotPrediction(value: timeString, confidence: 1.0, source: .manual)
            result.eventDay = SlotPrediction(value: dayString, confidence: 1.0, source: .manual)
            result.eventTime = SlotPrediction(value: timeString, confidence: 1.0, source: .manual)
        }
        
        return result
    }
    
    // MARK: - Snackbar Messages
    
    func showSuccess(_ message: String, title: String = "Success") {
        snackbarMessage = message
        snackbarTitle = title
        snackbarType = .success
        showSnackbar = true
        
        // Auto-dismiss after 2.5 seconds
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            showSnackbar = false
        }
    }
    
    func showError(_ message: String, title: String = "Error") {
        snackbarMessage = message
        snackbarTitle = title
        snackbarType = .error
        showSnackbar = true
        
        // Auto-dismiss after 3 seconds for errors
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            showSnackbar = false
        }
    }
    
    func showSnack(_ message: String, title: String = "") {
        snackbarMessage = message
        snackbarTitle = title
        showSnackbar = true
    }
    
    // MARK: - Helper Methods for View Compatibility
    
    func warmupServices() {
        // Warmup NLP service
        Task {
            _ = await NLPService.shared.parse(text: "warmup")
        }
    }
    
    func cancelParsing(for lineId: UUID) {
        debounceTasks[lineId]?.cancel()
        debounceTasks.removeValue(forKey: lineId)
    }
    

    
    func processLines() async {
        // Process all non-empty lines
        let nonEmptyLines = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        var successCount = 0
        var errorCount = 0
        var succeededLineIds: [UUID] = []
        var failedLineIds: [UUID] = []
        
        for line in nonEmptyLines {
            let results = lineParsingResults[line.id] ?? []
            guard let intentItem = results.first(where: { $0.field == "Intent" }) else {
                errorCount += 1
                failedLineIds.append(line.id)
                lineStore.updateStatus(for: line.id, status: .error)
                continue
            }
            
            let intent = NotepadFormatter.normalizeIntentForCheck(intentItem.value)
            let parsedResult = convertToParseResult(from: results, for: line.id)
            let entry = ParsedNotepadEntry.from(parsedResult: parsedResult, originalText: line.text)

            // Then handle intent-specific actions
            switch intent {
            case "event":
                do {
                    _ = try await eventKitManager.createEvent(
                        from: parsedResult,
                        originalText: line.text,
                        lineId: line.id,
                        location: locationManager.getLocation(for: line.id),
                        url: locationManager.getURL(for: line.id)
                    )
                    await MainActor.run { notepadEntryStore.addEntry(entry) }
                    successCount += 1
                    succeededLineIds.append(line.id)
                } catch {
                    showError("Failed to create event: \(error.localizedDescription)")
                    lineStore.updateStatus(for: line.id, status: .error)
                    errorCount += 1
                    failedLineIds.append(line.id)
                }
                
            case "reminder":
                do {
                    _ = try await eventKitManager.createReminder(
                        from: parsedResult,
                        originalText: line.text,
                        lineId: line.id,
                        location: locationManager.getLocation(for: line.id),
                        url: locationManager.getURL(for: line.id)
                    )
                    await MainActor.run { notepadEntryStore.addEntry(entry) }
                    successCount += 1
                    succeededLineIds.append(line.id)
                } catch {
                    showError("Failed to create reminder: \(error.localizedDescription)")
                    lineStore.updateStatus(for: line.id, status: .error)
                    errorCount += 1
                    failedLineIds.append(line.id)
                }
                
            case "work_start":
                do {
                    try await workSessionManager.handleWorkStart(result: parsedResult, originalText: line.text)
                    await MainActor.run { notepadEntryStore.addEntry(entry) }
                    successCount += 1
                    succeededLineIds.append(line.id)
                } catch {
                    showError("Failed to start work session: \(error.localizedDescription)")
                    lineStore.updateStatus(for: line.id, status: .error)
                    errorCount += 1
                    failedLineIds.append(line.id)
                }
                
            case "work_end":
                do {
                    try await workSessionManager.handleWorkEnd(result: parsedResult, originalText: line.text)
                    await MainActor.run { notepadEntryStore.addEntry(entry) }
                    successCount += 1
                    succeededLineIds.append(line.id)
                } catch {
                    showError("Failed to end work session: \(error.localizedDescription)")
                    lineStore.updateStatus(for: line.id, status: .error)
                    errorCount += 1
                    failedLineIds.append(line.id)
                }
                
            case "meal", "expense", "income", "journal", "activity", "calorie_adjustment":
                await MainActor.run { notepadEntryStore.addEntry(entry) }
                successCount += 1
                succeededLineIds.append(line.id)
                
            default:
                errorCount += 1
                failedLineIds.append(line.id)
                lineStore.updateStatus(for: line.id, status: .error)
            }
        }
        
        // Clear lines after processing
        if failedLineIds.isEmpty {
            resetLines()
        } else {
            // Remove only the successful lines; keep failed ones for retry
            for id in succeededLineIds {
                lineParsingResults.removeValue(forKey: id)
                _ = lineStore.deleteLine(id)
            }
            if let firstFailed = failedLineIds.first {
                lineStore.focusedId = firstFailed
            }
        }
        
        // Show appropriate message
        if errorCount == 0 {
            showSuccess("Processed \(successCount) item(s). All succeeded.", title: "Processing Complete")
        } else {
            // Try to find a specific error message from the failed lines
            var specificErrorMessage: String?
            for id in failedLineIds {
                if let results = lineParsingResults[id],
                   let errorItem = results.first(where: { !$0.isValid && $0.errorMessage != nil }) {
                    specificErrorMessage = errorItem.errorMessage
                    break
                }
            }
            
            if let specificError = specificErrorMessage {
                showError(specificError, title: "Validation Error")
            } else if successCount > 0 {
                showError("Processed \(successCount + errorCount) items: \(successCount) succeeded, \(errorCount) failed.", title: "Partial Success")
            } else {
                showError("No items processed. \(errorCount) failed.", title: "Processing Failed")
            }
        }
    }
    
    // MARK: - Work Session Properties (Delegated)
    
    var showWorkSessionConfirmation: Bool {
        get { workSessionManager.showWorkSessionConfirmation }
        set { workSessionManager.showWorkSessionConfirmation = newValue }
    }
    
    var pendingWorkStart: (date: Date, time: String, object: String?)? {
        get { workSessionManager.pendingWorkStart }
        set { workSessionManager.pendingWorkStart = newValue }
    }
    
    var existingWorkSession: WorkSessionStruct? {
        get { workSessionManager.existingWorkSession }
        set { workSessionManager.existingWorkSession = newValue }
    }
    
    // MARK: - Helper Methods for View
    
    func faviconURL(for urlString: String) -> URL? {
        // Extract domain from URL
        guard let url = URL(string: urlString),
              let host = url.host else {
            return nil
        }
        
        // Use Google Favicon API
        let faviconURLString = "https://www.google.com/s2/favicons?domain=\(host)&sz=32"
        return URL(string: faviconURLString)
    }
    
    func parseSources(from jsonString: String?) -> [CalorieSource] {
        guard let jsonString = jsonString,
              let jsonData = jsonString.data(using: .utf8) else {
            return []
        }
        
        do {
            let sources = try JSONDecoder().decode([CalorieSource].self, from: jsonData)
            return sources
        } catch {
            return []
        }
    }
}
