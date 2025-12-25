import SwiftUI

struct EditEntrySheet: View {
    let entry: ParsedNotepadEntry
    @State private var text: String
    @Environment(\.dismiss) private var dismiss
    
    var onSave: (String) -> Void
    
    init(entry: ParsedNotepadEntry, onSave: @escaping (String) -> Void) {
        self.entry = entry
        _text = State(initialValue: entry.originalText)
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Entry Text", text: $text, axis: .vertical)
                        .lineLimit(3...10)
                } footer: {
                    Text("Editing this entry will re-process it. This is useful for fixing amounts, calories, or categorization errors.")
                }
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
