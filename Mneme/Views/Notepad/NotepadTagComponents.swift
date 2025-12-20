import SwiftUI

// MARK: - Tag Chip

struct TagChip: View {
    let tag: String
    let color: Color
    let isSelected: Bool
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var showMenu = false
    
    private var backgroundColor: Color {
        isSelected ? color.opacity(0.2) : Color.appBackground(colorScheme: colorScheme)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(tag.capitalized)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(backgroundColor)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
        .contentShape(Capsule())
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            showMenu = true
        }
        .confirmationDialog("Tag Actions", isPresented: $showMenu, titleVisibility: .hidden) {
            Button("Edit") { onEdit() }
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) { }
        }
    }
}

// MARK: - Add Tag Sheet

struct AddTagSheet: View {
    let eventId: UUID
    let initialName: String
    let onSave: (String, String) -> Void
    let onCancel: () -> Void
    
    @State private var tagName: String
    @State private var selectedColor: String
    @FocusState private var isFocused: Bool
    
    init(eventId: UUID, initialName: String, onSave: @escaping (String, String) -> Void, onCancel: @escaping () -> Void) {
        self.eventId = eventId
        self.initialName = initialName
        self.onSave = onSave
        self.onCancel = onCancel
        _tagName = State(initialValue: initialName)
        _selectedColor = State(initialValue: initialName.isEmpty ? TagStore.defaultColor() : TagStore.colorForTag(initialName))
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Tag Name") {
                    TextField("Enter tag name", text: $tagName)
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                        .autocorrectionDisabled()
                        .focused($isFocused)
                }
                
                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 16) {
                        ForEach(TagStore.availableColors, id: \.name) { colorInfo in
                            Button {
                                selectedColor = colorInfo.name
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(colorInfo.color)
                                        .frame(width: 44, height: 44)
                                    if selectedColor == colorInfo.name {
                                        Image(systemName: "checkmark")
                                            .font(.body.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Add Tag")
            #if os(iOS)
.navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.count >= 2 {
                            onSave(trimmed, selectedColor)
                        }
                    }
                    .disabled(tagName.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isFocused = true
                }
            }
        }
    }
}

// MARK: - Edit Tag Sheet

struct EditTagSheet: View {
    let eventId: UUID
    let tagId: UUID
    let currentTag: String
    let currentColorName: String
    let onSave: (String, String, String) -> Void
    let onCancel: () -> Void
    
    @State private var tagName: String
    @State private var selectedColor: String
    @FocusState private var isFocused: Bool
    
    init(eventId: UUID, tagId: UUID, currentTag: String, currentColorName: String, onSave: @escaping (String, String, String) -> Void, onCancel: @escaping () -> Void) {
        self.eventId = eventId
        self.tagId = tagId
        self.currentTag = currentTag
        self.currentColorName = currentColorName
        self.onSave = onSave
        self.onCancel = onCancel
        _tagName = State(initialValue: currentTag)
        _selectedColor = State(initialValue: currentColorName.isEmpty ? TagStore.colorForTag(currentTag) : currentColorName)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Tag Name") {
                    TextField("Enter tag name", text: $tagName)
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                        .autocorrectionDisabled()
                        .focused($isFocused)
                }
                
                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 50))], spacing: 16) {
                        ForEach(TagStore.availableColors, id: \.name) { colorInfo in
                            Button {
                                selectedColor = colorInfo.name
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(colorInfo.color)
                                        .frame(width: 44, height: 44)
                                    if selectedColor == colorInfo.name {
                                        Image(systemName: "checkmark")
                                            .font(.body.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Edit Tag")
            #if os(iOS)
.navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            onSave(currentTag, trimmed, selectedColor)
                        }
                    }
                    .disabled(tagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || 
                             (tagName.trimmingCharacters(in: .whitespacesAndNewlines) == currentTag && selectedColor == currentColorName))
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isFocused = true
                }
            }
        }
    }
}
