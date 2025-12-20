import SwiftUI
import EventKit

@MainActor
struct ReminderDetailSheet: View {
    let reminder: ReminderItem
    let onDismiss: () -> Void
    let onRequestEdit: (ReminderItem) -> Void
    let onRequestDelete: (ReminderItem) -> Void
    let onDataChanged: (() -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tagStore: TagStore
    @State private var ekReminder: EKReminder?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false
    @State private var showEditor = false
    
    init(reminder: ReminderItem, onDismiss: @escaping () -> Void, onRequestEdit: @escaping (ReminderItem) -> Void, onRequestDelete: @escaping (ReminderItem) -> Void, onDataChanged: (() -> Void)? = nil) {
        self.reminder = reminder
        self.onDismiss = onDismiss
        self.onRequestEdit = onRequestEdit
        self.onRequestDelete = onRequestDelete
        self.onDataChanged = onDataChanged
    }
    
    private let eventKitService = EventKitService.shared
    
    private var tagTargetId: UUID {
        if let identifier = reminder.ekReminder?.calendarItemIdentifier {
            return TagStore.stableUUID(for: identifier)
        }
        return reminder.id
    }
    
    private var assignedTags: [Tag] {
        tagStore.getTags(for: tagTargetId)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
    
    private var dueDateText: String? {
        guard let dueDate = reminder.dueDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        DateHelper.applySettings(formatter)
        return formatter.string(from: dueDate)
    }
    
    private var structuredLocationTitle: String? {
        return ekReminder?.alarms?.compactMap { $0.structuredLocation?.title }.first
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let ekReminder = ekReminder {
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(reminder.title)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                
                                if let dueDateText = dueDateText {
                                    Label(dueDateText, systemImage: "calendar.badge.clock")
                                } else {
                                    Label("No due date", systemImage: "calendar.badge.clock")
                                        .foregroundStyle(.secondary)
                                }
                                
                                if !assignedTags.isEmpty {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(assignedTags, id: \.id) { tag in
                                                TagChip(
                                                    tag: tag.displayName,
                                                    color: tag.color,
                                                    isSelected: true,
                                                    onTap: {},
                                                    onEdit: {},
                                                    onDelete: {}
                                                )
                                            }
                                        }
                                        .padding(.horizontal, 4)
                                    }
                                }
                                
                                if let url = ekReminder.url {
                                    Link(destination: url) {
                                        Label(url.absoluteString, systemImage: "link")
                                            .lineLimit(1)
                                    }
                                    .padding(.vertical, 4)
                                }
                                
                                if let locationName = structuredLocationTitle {
                                    LocationPreviewSection(locationName: locationName)
                                }
                                
                                if let notes = ekReminder.notes, !notes.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Notes")
                                            .font(.headline)
                                        Text(notes)
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .padding(.bottom, 80)
                        }
                        
                        VStack(spacing: 0) {
                            Divider()
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("Delete Reminder")
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(.red)
                                    Spacer()
                                }
                                .frame(height: 50)
                                .background(Color(uiColor: .systemBackground))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if let errorMessage = errorMessage {
                    ContentUnavailableView("Reminder Not Available", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else {
                    ContentUnavailableView("Reminder Not Available", systemImage: "list.bullet", description: Text("This reminder could not be found."))
                }
            }
            .navigationTitle("Reminder Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismissSheet() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Edit") {
                        showEditor = true
                    }
                }
            }
        }
        .task {
            await loadReminder()
        }
        .sheet(isPresented: $showEditor) {
            ReminderEditSheetWrapper(
                reminder: reminder,
                eventKitService: eventKitService,
                onDismiss: {
                    showEditor = false
                    Task {
                        await loadReminder()
                        onDataChanged?()
                    }
                },
                onRequestDelete: { item in
                    showEditor = false
                    onRequestDelete(item)
                }
            )
            .environmentObject(tagStore)
        }
        .onDisappear {
            onDismiss()
        }
        .alert("Delete Reminder", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                dismissSheet()
                onRequestDelete(reminder)
            }
        } message: {
            Text("Are you sure you want to delete this reminder?")
        }
    }
    
    private func dismissSheet() {
        dismiss()
    }
    
    private func loadReminder() async {
        isLoading = true
        var resultReminder = reminder.ekReminder
        if let identifier = reminder.ekReminder?.calendarItemIdentifier {
            resultReminder = eventKitService.getReminder(byIdentifier: identifier) ?? resultReminder
        }
        await MainActor.run {
            self.ekReminder = resultReminder
            self.isLoading = false
            if resultReminder == nil {
                self.errorMessage = "Reminder may have been removed or access was revoked."
            }
        }
    }
}
