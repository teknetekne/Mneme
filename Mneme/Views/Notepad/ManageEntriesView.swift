import SwiftUI

struct ManageEntriesView: View {
    let date: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var store = NotepadEntryStore.shared
    @State private var editingEntry: ParsedNotepadEntry?
    @State private var isProcessing = false
    
    private var entries: [ParsedNotepadEntry] {
        store.getEntries(for: date).filter { entry in
            guard let intent = entry.intent?.lowercased() else { return true }
            return intent != "event" && intent != "reminder" && intent != "calendar_event"
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    ContentUnavailableView("No Entries", systemImage: "text.badge.minus", description: Text("No notepad entries found for this day."))
                } else {
                    Section {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.originalText)
                                    .font(.body)
                                
                                HStack {
                                    if let intent = entry.intent {
                                        Text(intent.capitalized)
                                            .font(.caption2).bold()
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(intentColor(for: intent).opacity(0.2)))
                                            .foregroundStyle(intentColor(for: intent))
                                    }
                                    
                                    Text(entry.date, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.deleteEntry(entry)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                
                                Button {
                                    editingEntry = entry
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(entries.count) Entries")
                            Text("Swipe left to delete or edit.")
                                .font(.caption)
                                .textCase(nil)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .contentMargins(.top, 16, for: .scrollContent)
            .sheet(item: $editingEntry) { entry in
                EditEntrySheet(entry: entry) { newText in
                    Task {
                        await reprocessEntry(entry, newText: newText)
                    }
                }
            }
            .overlay {
                if isProcessing {
                    ProgressView("Processing...")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .navigationTitle(dateTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func intentColor(for intent: String) -> Color {
        switch intent.lowercased() {
        case "meal": return .orange
        case "income": return .green
        case "expense": return .red
        case "work_session": return .blue
        case "journal": return .purple
        case "calorie_adjustment": return .orange
        default: return .secondary
        }
    }
    
    @MainActor
    private func reprocessEntry(_ oldEntry: ParsedNotepadEntry, newText: String) async {
        isProcessing = true
        defer { isProcessing = false }
        
        var finalResult: ParsedResult
        var items: [ParsingResultItem] = []
        
        // 1. Check for variable expression first
        if let expressionResult = VariableHandler.shared.evaluateExpression(newText, baseCurrency: CurrencySettingsStore.shared.baseCurrency) {
            
            let intent: String
            if expressionResult.field == "Calories" {
                intent = "meal"
            } else {
                intent = expressionResult.value.contains("-") ? "expense" : "income"
            }
            
            // Construct result manually from expression
            let extractedCurrency = TextParsingHelpers.extractCurrency(from: expressionResult.value) ?? CurrencySettingsStore.shared.baseCurrency
            
            finalResult = ParsedResult(
                intent: SlotPrediction(value: intent, confidence: 1.0, source: .manual),
                currency: SlotPrediction(value: extractedCurrency, confidence: 1.0, source: .manual),
                amount: expressionResult.field == "Amount" ? SlotPrediction(value: TextParsingHelpers.extractFirstNumber(from: expressionResult.value) ?? 0, confidence: 1.0, source: .manual) : nil,
                mealKcal: expressionResult.field == "Calories" ? SlotPrediction(value: TextParsingHelpers.extractFirstNumber(from: expressionResult.value) ?? 0, confidence: 1.0, source: .manual) : nil
            )
            // No need for handler items since we constructed the result directly
            
        } else {
            // 2. Standard NLP Flow
            let nlpResult = await NLPService.shared.parse(text: newText)
            let intent = nlpResult.intent?.value ?? "none"
            let handler = HandlerFactory.handler(for: intent)
            items = await handler.handle(result: nlpResult, text: newText, lineId: UUID())
            
            finalResult = nlpResult
        }
        
        // 3. Map handler items back to result fields (if any)
        for item in items {
            if item.field == "Amount", let val = TextParsingHelpers.extractFirstNumber(from: item.value) {
                finalResult.amount = SlotPrediction(value: val, confidence: 1.0, source: .manual)
            }
            if item.field == "Calories", let val = TextParsingHelpers.extractFirstNumber(from: item.value) {
                finalResult.mealKcal = SlotPrediction(value: val, confidence: 1.0, source: .manual)
            }
            // ... add others as needed
        }
        
        let newEntry = ParsedNotepadEntry.from(
            parsedResult: finalResult,
            originalText: newText,
            date: oldEntry.date // Keep original date!
        )
        
        await MainActor.run {
            store.deleteEntry(oldEntry)
            store.addEntry(newEntry)
        }
    }
}

#Preview {
    ManageEntriesView(date: Date())
}
