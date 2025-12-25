import SwiftUI

struct DraftEventEditor: View {
    @Binding var title: String
    @Binding var date: Date
    @Binding var isReminder: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        .autocorrectionDisabled()
                }
                
                Section {
                    DatePicker(
                        selection: $date,
                        displayedComponents: [.date, .hourAndMinute]
                    ) {
                        Text("Date & Time")
                    }
                }
                
                Section {
                    Picker("Type", selection: $isReminder) {
                        Text("Event").tag(false)
                        Text("Reminder").tag(true)
                    }
                }
            }
            .navigationTitle("Edit Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                    }
                }
            }
        }
    }
}
