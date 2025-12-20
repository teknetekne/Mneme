import SwiftUI
import EventKit

@MainActor
struct EventDetailSheet: View {
    let event: CalendarEvent
    let onDismiss: () -> Void
    let onDataChanged: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tagStore: TagStore
    @State private var ekEvent: EKEvent?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showEditor = false
    @State private var showDeleteConfirmation = false
    
    private let eventKitService = EventKitService.shared
    
    private var tagTargetId: UUID {
        TagStore.stableUUID(for: event.eventIdentifier)
    }
    
    private var assignedTags: [Tag] {
        tagStore.getTags(for: tagTargetId)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let ekEvent = ekEvent {
                    VStack(spacing: 0) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                EventHeadlineView(event: ekEvent)
                                
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
                                
                                if let url = ekEvent.url {
                                    Link(destination: url) {
                                        Label(url.absoluteString, systemImage: "link")
                                            .lineLimit(1)
                                    }
                                    .padding(.vertical, 4)
                                }
                                if let locationName = ekEvent.location, !locationName.isEmpty {
                                    LocationPreviewSection(locationName: locationName)
                                }
                                if let notes = ekEvent.notes, !notes.isEmpty {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("Notes")
                                            .font(.headline)
                                        Text(notes)
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
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
                                    Text("Delete Event")
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
                    ContentUnavailableView("Event Not Available", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else {
                    ContentUnavailableView("Event Not Available", systemImage: "calendar", description: Text("This event could not be found."))
                }
            }
            .navigationTitle("Event Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismissSheet()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Edit") {
                        showEditor = true
                    }
                    .disabled(ekEvent == nil)
                }
            }
        }
        .task {
            await loadEvent()
        }
        .sheet(isPresented: $showEditor) {
            EventEditorView(event: event) {
                showEditor = false
                Task {
                    await loadEvent()
                    onDataChanged()
                }
            }
            .environmentObject(tagStore)
        }
        .onDisappear {
            onDismiss()
        }
        .alert("Delete Event", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteEvent()
            }
        } message: {
            Text("Are you sure you want to delete this event?")
        }
    }
    
    private func dismissSheet() {
        dismiss()
    }
    
    private func deleteEvent() {
        guard let ekEvent = ekEvent else { return }
        
        do {
            try eventKitService.deleteEvent(ekEvent)
            onDataChanged()
            dismissSheet()
        } catch {
            errorMessage = "Failed to delete event: \(error.localizedDescription)"
        }
    }
    
    private func loadEvent() async {
        isLoading = true
        let ekEvent = eventKitService.getEvent(byIdentifier: event.eventIdentifier)
        
        await MainActor.run {
            self.ekEvent = ekEvent
            self.isLoading = false
            self.errorMessage = ekEvent == nil ? "Event may have been removed or access was revoked." : nil
        }
    }
}

private struct EventHeadlineView: View {
    let event: EKEvent
    private var formatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .full
        f.timeStyle = .short
        DateHelper.applySettings(f)
        return f
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.title)
                .font(.title2)
                .fontWeight(.semibold)
            HStack {
                Label(formatter.string(from: event.startDate), systemImage: "calendar")
                Spacer()
            }
            if event.endDate > event.startDate {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text("\(timeString(event.startDate)) – \(timeString(event.endDate))")
                }
                .foregroundStyle(.secondary)
                .font(.subheadline)
            }
        }
    }
    
    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        DateHelper.applyTimeFormat(formatter)
        return formatter.string(from: date)
    }
}
