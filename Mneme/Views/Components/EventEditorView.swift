import SwiftUI
import EventKit
import MapKit

@MainActor
struct EventEditorView: View {
    let event: CalendarEvent
    let onDismiss: () -> Void
    
    @StateObject private var eventKitService = EventKitService.shared
    @EnvironmentObject private var tagStore: TagStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var notes: String
    @State private var location: String
    @State private var showDeleteConfirmation = false
    @State private var showLocationSearch = false
    @State private var showAddTagSheet = false
    @State private var editingTag: Tag?
    @State private var errorMessage: String? = nil
    @Environment(\.dismiss) private var dismiss
    
    private var tagTargetId: UUID {
        TagStore.stableUUID(for: event.eventIdentifier)
    }
    
    private var assignedTagIds: Set<UUID> {
        Set(tagStore.getTags(for: tagTargetId).map(\.id))
    }
    
    private var allTags: [Tag] {
        tagStore.getAllTags()
    }
    
    private var sortedTags: [Tag] {
        allTags.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
    
    init(event: CalendarEvent, onDismiss: @escaping () -> Void) {
        self.event = event
        self.onDismiss = onDismiss
        _title = State(initialValue: event.title)
        _startDate = State(initialValue: Date())
        _endDate = State(initialValue: Date())
        _notes = State(initialValue: "")
        _location = State(initialValue: "")
    }
    
    var body: some View {
        NavigationStack {
            Form {
                titleSection
                dateSection
                locationSection
                notesSection
                tagsSection
                deleteSection
            }
            .navigationTitle("Edit Event")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .task {
                await loadEventData()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEvent()
                    }
                }
            }
            .alert("Delete Event", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteEvent()
                }
            } message: {
                Text("Are you sure you want to delete this event?")
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
            .sheet(isPresented: $showLocationSearch) {
                LocationSearchView { locationName, _ in
                    location = locationName
                    showLocationSearch = false
                }
            }
            .sheet(isPresented: $showAddTagSheet) {
                AddTagSheet(
                    eventId: tagTargetId,
                    initialName: "",
                    onSave: { name, colorName in
                        attachNewTag(name: name, colorName: colorName)
                        showAddTagSheet = false
                    },
                    onCancel: {
                        showAddTagSheet = false
                    }
                )
            }
            .sheet(item: $editingTag) { tag in
                EditTagSheet(
                    eventId: tagTargetId,
                    tagId: tag.id,
                    currentTag: tag.name,
                    currentColorName: tag.colorName,
                    onSave: { _, newName, colorName in
                        updateTag(tagId: tag.id, newName: newName, colorName: colorName)
                        editingTag = nil
                    },
                    onCancel: {
                        editingTag = nil
                    }
                )
            }
        }
    }
    
    private func toggleTag(_ tag: Tag, isSelected: Bool) {
        Task {
            do {
                if isSelected {
                    try await tagStore.unassignTag(tag.id, from: tagTargetId)
                } else {
                    try await tagStore.assignTag(tag.id, to: tagTargetId)
                }
            } catch {
            }
        }
    }
    
    private func attachNewTag(name: String, colorName: String) {
        Task {
            do {
                try await tagStore.assignTagByName(name, to: tagTargetId, colorName: colorName)
            } catch {
            }
        }
    }
    
    private func updateTag(tagId: UUID, newName: String, colorName: String) {
        Task {
            do {
                try await tagStore.updateTag(id: tagId, newName: newName, newColorName: colorName)
            } catch {
            }
        }
    }
    
    private func deleteTag(_ tag: Tag) {
        Task {
            do {
                try await tagStore.deleteTag(id: tag.id)
            } catch {
            }
        }
    }
    
    private func saveEvent() {
        guard let ekEvent = eventKitService.getEvent(byIdentifier: event.eventIdentifier) else {
            errorMessage = "Event not found"
            return
        }
        
        do {
            try eventKitService.updateEvent(
                ekEvent,
                title: title,
                startDate: startDate,
                endDate: endDate,
                notes: notes.isEmpty ? nil : notes,
                location: location.isEmpty ? nil : location,
                url: ekEvent.url
            )
            onDismiss()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func loadEventData() async {
        guard let ekEvent = eventKitService.getEvent(byIdentifier: event.eventIdentifier) else {
            return
        }
        await MainActor.run {
            startDate = ekEvent.startDate
            endDate = ekEvent.endDate
            notes = ekEvent.notes ?? ""
            location = ekEvent.location ?? ""
        }
    }
    
    private func deleteEvent() {
        guard let ekEvent = eventKitService.getEvent(byIdentifier: event.eventIdentifier) else {
            errorMessage = "Event not found"
            return
        }
        
        do {
            try eventKitService.deleteEvent(ekEvent)
            onDismiss()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Subviews
    
    private var titleSection: some View {
        Section {
            TextField("Title", text: $title)
        }
    }
    
    private var dateSection: some View {
        Section {
            DatePicker("Start", selection: $startDate)
            DatePicker("End", selection: $endDate)
        }
    }
    
    private var locationSection: some View {
        Section {
            if location.isEmpty {
                Button {
                    showLocationSearch = true
                } label: {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                        Text("Add Location")
                    }
                }
            } else {
                HStack {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.red)
                    Text(location)
                    Spacer()
                    Button {
                        location = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private var notesSection: some View {
        Section {
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }
    
    private var tagsSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sortedTags, id: \.id) { tag in
                        let isSelected = assignedTagIds.contains(tag.id)
                        TagChip(
                            tag: tag.displayName,
                            color: tag.color,
                            isSelected: isSelected,
                            onTap: {
                                toggleTag(tag, isSelected: isSelected)
                            },
                            onEdit: {
                                editingTag = tag
                            },
                            onDelete: {
                                deleteTag(tag)
                            }
                        )
                    }
                    
                    Button {
                        showAddTagSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.caption2)
                                .fontWeight(.medium)
                            Text("Add")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(white: colorScheme == .dark ? 1 : 0, opacity: colorScheme == .dark ? 0.15 : 0.08))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
            }
        } header: {
            Text("Tags")
        }
    }
    
    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Text("Delete Event")
                    Spacer()
                }
            }
        }
    }
}
