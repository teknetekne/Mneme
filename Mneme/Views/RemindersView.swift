import SwiftUI
import EventKit
import MapKit
#if os(iOS)
import UIKit
#endif

fileprivate enum ReminderFilter {
    case today
    case scheduled
    case all
    case completed
}

struct RemindersView: View {
    @State private var showSearch = false
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        Color.appBackground(colorScheme: colorScheme)
    }

    @State private var reminders: [ReminderItem] = []
    @StateObject private var eventKitService = EventKitService.shared
    @StateObject private var tagStore = TagStore.shared
    @State private var isLoading = false
    @State private var selectedFilter: ReminderFilter? = .all
    @State private var selectedTagFilter: UUID? = nil
    @State private var editingReminder: ReminderItem? = nil
    @State private var showEditSheet = false
    @State private var selectedReminder: ReminderItem?
    @State private var showCreateReminder = false
    @State private var scrollToId: UUID?
    
    private var filteredReminders: [ReminderItem] {
        // Early return if no reminders
        guard !reminders.isEmpty else { return [] }
        
        var filtered: [ReminderItem]
        
        if let filter = selectedFilter {
            let today = Calendar.current.startOfDay(for: Date())
            
            switch filter {
            case .today:
                filtered = reminders.filter { reminder in
                    guard let dueDate = reminder.dueDate else { return false }
                    let reminderDay = Calendar.current.startOfDay(for: dueDate)
                    return reminderDay == today && !reminder.isCompleted
                }
            case .scheduled:
                filtered = reminders.filter { reminder in
                    reminder.dueDate != nil && !reminder.isCompleted
                }
            case .all:
                filtered = reminders.sorted { reminder1, reminder2 in
                    if reminder1.isCompleted != reminder2.isCompleted {
                        return !reminder1.isCompleted
                    }
                    return false
                }
            case .completed:
                filtered = reminders.filter { $0.isCompleted }
            }
        } else {
            filtered = reminders.filter { !$0.isCompleted }
        }
        
        // Apply tag filter if selected
        if let tagId = selectedTagFilter {
            filtered = filtered.filter { reminder in
                let tagTargetId: UUID
                if let identifier = reminder.ekReminder?.calendarItemIdentifier {
                    tagTargetId = TagStore.stableUUID(for: identifier)
                } else {
                    tagTargetId = reminder.id
                }
                let tags = tagStore.getTags(for: tagTargetId)
                return tags.contains { $0.id == tagId }
            }
        }
        
        return filtered
    }
    
    private var smartLists: [SmartList] {
        // Optimize: calculate all counts in a single pass
        let today = Calendar.current.startOfDay(for: Date())
        var todayCount = 0
        var scheduledCount = 0
        var completedCount = 0
        
        for reminder in reminders {
            if reminder.isCompleted {
                completedCount += 1
            } else {
                if reminder.dueDate != nil {
                    scheduledCount += 1
                    if let dueDate = reminder.dueDate {
                        let reminderDay = Calendar.current.startOfDay(for: dueDate)
                        if reminderDay == today {
                            todayCount += 1
                        }
                    }
                }
            }
        }
        
        return [
            SmartList(
                title: "All",
                systemImage: "tray.fill",
                count: reminders.count,
                color: .gray
            ),
            SmartList(
                title: "Today",
                systemImage: "calendar",
                count: todayCount,
                color: .blue
            ),
            SmartList(
                title: "Scheduled",
                systemImage: "calendar.badge.clock",
                count: scheduledCount,
                color: .orange
            ),
            SmartList(
                title: "Completed",
                systemImage: "checkmark.circle.fill",
                count: completedCount,
                color: .green
            )
        ]
    }

    private let listContentHorizontalInset: CGFloat = 20

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()
            
            ScrollViewReader { proxy in
                remindersList
                    .onChange(of: scrollToId) { _, id in
                        if let id = id {
                            withAnimation {
                                proxy.scrollTo(id, anchor: .center)
                            }
                            scrollToId = nil
                        }
                    }
            }
                .scrollContentBackground(.hidden)
                .listStyle(.inset)
                .listSectionSeparator(.hidden)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: filteredReminders.count)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedFilter)
                .onAppear {
                    loadReminders()
                }
                .refreshable {
                    await loadRemindersAsync()
                }
                .onChange(of: editingReminder) { _, newValue in
                    showEditSheet = newValue != nil
                }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showCreateReminder = true
                } label: {
                    Image(systemName: "plus")
                }
                .sheet(isPresented: $showCreateReminder) {
                    CreateReminderView {
                        showCreateReminder = false
                        Task {
                            await loadRemindersAsync()
                        }
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSearch.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .sheet(isPresented: $showSearch) {
                    ReminderSearchView(onSelect: { reminder in
                        showSearch = false
                        selectedFilter = .all
                        selectedTagFilter = nil
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            scrollToId = reminder.id
                        }
                    })
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            editSheetContent
                .environmentObject(tagStore)
        }
        .sheet(item: $selectedReminder) { reminder in
            ReminderDetailSheet(
                reminder: reminder,
                onDismiss: { selectedReminder = nil },
                onRequestEdit: { item in
                    editingReminder = item
                },
                onRequestDelete: { item in
                    deleteReminder(item)
                },
                onDataChanged: {
                    Task {
                        await loadRemindersAsync()
                    }
                }
            )
            .environmentObject(tagStore)
        }
    }
    
    private var remindersList: some View {
        List {
            Section {
                SmartListsGrid(
                    smartLists: smartLists,
                    selectedFilter: selectedFilter,
                    selectedTagFilter: $selectedTagFilter,
                    tagStore: tagStore,
                    onFilterSelected: { filterTitle in
                        handleFilterSelection(filterTitle)
                    },
                    onDoubleTap: { filterTitle in
                        if filterTitle != "All" {
                            selectedFilter = .all
                            selectedTagFilter = nil
                        }
                    }
                )
                #if os(iOS)
                .padding(EdgeInsets(top: 6, leading: listContentHorizontalInset, bottom: 6, trailing: listContentHorizontalInset))
                .listRowInsets(EdgeInsets())
                #else
                .padding(.horizontal, listContentHorizontalInset)
                .padding(.vertical, 6)
                .listRowInsets(.init())
                #endif
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                ForEach(filteredReminders) { reminder in
                    ReminderRow(
                        reminder: reminder,
                        onToggleComplete: {
                            toggleReminderCompletion(reminder)
                        },
                        onSelect: {
                            selectedReminder = reminder
                        }
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
        }
    }
    
    @ViewBuilder
    private var editSheetContent: some View {
        if let reminder = editingReminder {
            ReminderEditView(
                reminder: reminder,
                eventKitService: eventKitService,
                onSave: { updatedReminder in
                    // ReminderEditView already saves the reminder directly
                    // Just reload the list and close
                    Task {
                        await loadRemindersAsync()
                    }
                    editingReminder = nil
                },
                onCancel: {
                    editingReminder = nil
                },
                onDelete: {
                    deleteReminder(reminder)
                    editingReminder = nil
                }
            )
            .id(reminder.id)
        }
    }
    
    // MARK: - Data Loading
    
    private func loadReminders() {
        guard eventKitService.isAuthorized else {
            Task {
                let authorized = await eventKitService.requestFullAccess()
                if authorized {
                    await loadRemindersAsync()
                }
            }
            return
        }
        
        Task {
            await loadRemindersAsync()
        }
    }
    
    private func loadRemindersAsync() async {
        await MainActor.run {
            isLoading = true
        }
        
        let ekReminders = await eventKitService.getReminders(includeCompleted: true)
        
        await MainActor.run {
            reminders = ekReminders.map { ekReminder in
                let dueDate = resolveDueDate(for: ekReminder)
                // Use stable ID from calendarItemIdentifier
                return ReminderItem(
                    id: ReminderItem.stableId(from: ekReminder),
                    ekReminder: ekReminder,
                    title: ekReminder.title,
                    isCompleted: ekReminder.isCompleted,
                    priority: priorityFromEK(ekReminder.priority),
                    dueDate: dueDate
                )
            }
            isLoading = false
        }
    }

    private func resolveDueDate(for reminder: EKReminder) -> Date? {
        if let components = reminder.dueDateComponents {
            var calendar = components.calendar ?? Calendar.current
            calendar.timeZone = components.timeZone ?? calendar.timeZone
            return calendar.date(from: components)
        }
        
        return reminder.alarms?
            .compactMap { $0.absoluteDate }
            .min()
    }
    
    private func toggleReminderCompletion(_ reminder: ReminderItem) {
        guard let ekReminder = reminder.ekReminder else { return }
        let wasCompleted = reminder.isCompleted
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
                reminders[index].isCompleted.toggle()
            }
        }
        
        Task {
            do {
                if wasCompleted {
                    ekReminder.isCompleted = false
                    try eventKitService.saveReminder(ekReminder)
                } else {
                    try eventKitService.completeReminder(ekReminder)
                }
                await loadRemindersAsync()
            } catch {
            }
        }
    }
    
    private func updateReminder(_ reminder: ReminderItem) {
        guard let ekReminder = reminder.ekReminder else { return }
        
        Task {
            do {
                ekReminder.title = reminder.title
                if let dueDate = reminder.dueDate {
                    ekReminder.alarms?.forEach { ekReminder.removeAlarm($0) }
                    let alarm = EKAlarm(absoluteDate: dueDate)
                    ekReminder.addAlarm(alarm)
                }
                try eventKitService.saveReminder(ekReminder)
                await loadRemindersAsync()
            } catch {
            }
        }
    }
    
    private func deleteReminder(_ reminder: ReminderItem) {
        guard let ekReminder = reminder.ekReminder else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            reminders.removeAll { $0.id == reminder.id }
        }
        
        Task {
            do {
                try eventKitService.deleteReminder(ekReminder)
                await loadRemindersAsync()
            } catch {
            }
        }
    }
    
    private func priorityFromEK(_ priority: Int) -> ReminderPriority {
        switch priority {
        case 1: return .high
        case 5: return .medium
        case 9: return .low
        default: return .none
        }
    }
    
    private func handleFilterSelection(_ filterTitle: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            let newFilter: ReminderFilter?
            switch filterTitle {
            case "Today":
                newFilter = .today
            case "Scheduled":
                newFilter = .scheduled
            case "All":
                newFilter = .all
            case "Completed":
                newFilter = .completed
            default:
                newFilter = nil
            }
            
            // If clicking the same filter again, switch to All
            if selectedFilter == newFilter && newFilter != .all {
                selectedFilter = .all
                selectedTagFilter = nil
            } else {
                selectedFilter = newFilter
            }
        }
    }
}

// MARK: - Smart Lists Grid

private struct SmartListsGrid: View {
    let smartLists: [SmartList]
    let selectedFilter: ReminderFilter?
    @Binding var selectedTagFilter: UUID?
    let tagStore: TagStore
    let onFilterSelected: (String) -> Void
    let onDoubleTap: (String) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var showTagFilterSheet = false

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }
    
    private func filterForTitle(_ title: String) -> ReminderFilter? {
        switch title {
        case "Today": return .today
        case "Scheduled": return .scheduled
        case "All": return .all
        case "Completed": return .completed
        default: return nil
        }
    }
    
    private var allTags: [Tag] {
        tagStore.getAllTags().sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(smartLists) { item in
                    SmartListCard(
                        item: item,
                        isSelected: filterForTitle(item.title) == selectedFilter,
                        onTap: {
                            onFilterSelected(item.title)
                        },
                        onDoubleTap: {
                            // Double tap is now handled in handleFilterSelection
                            onDoubleTap(item.title)
                        }
                    )
                }
            }
            
            tagFilterDropdown
        }
        .padding(.vertical, 4)
    }
    
    private var tagFilterDropdown: some View {
        Button {
            showTagFilterSheet = true
        } label: {
            HStack(spacing: 8) {
                if let tagId = selectedTagFilter, let tag = allTags.first(where: { $0.id == tagId }) {
                    Circle()
                        .fill(tag.color)
                        .frame(width: 6, height: 6)
                    Text("Filter: \(tag.displayName)")
                        .foregroundStyle(.primary)
                } else {
                    Image(systemName: "tag")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                    Text("Filter by Tag")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .font(.body)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(white: colorScheme == .dark ? 1 : 0, opacity: colorScheme == .dark ? 0.1 : 0.05))
            )
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showTagFilterSheet) {
            tagFilterSheet
        }
    }
    
    private var tagFilterSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedTagFilter = nil
                        showTagFilterSheet = false
                    } label: {
                        HStack {
                            Text("All Tags")
                            Spacer()
                            if selectedTagFilter == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    
                    if !allTags.isEmpty {
                        ForEach(allTags) { tag in
                            Button {
                                selectedTagFilter = tag.id
                                showTagFilterSheet = false
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(tag.color)
                                        .frame(width: 12, height: 12)
                                    Text(tag.displayName)
                                    Spacer()
                                    if selectedTagFilter == tag.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Filter by Tag")
            #if os(iOS)
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            #else
            .listStyle(.inset)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showTagFilterSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct SmartListCard: View {
    let item: SmartList
    let isSelected: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var tapCount = 0
    @State private var tapTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(item.color.opacity(isSelected ? 0.30 : 0.20))
                    .frame(width: 36, height: 36)

                Image(systemName: item.systemImage)
                    .imageScale(.medium)
                    .foregroundStyle(item.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text("\(item.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(item.color)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? item.color.opacity(0.5) : cardBorder, lineWidth: isSelected ? 1.5 : 0.8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            tapTask?.cancel()
            tapCount += 1
            
            tapTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                if !Task.isCancelled {
                    if tapCount == 1 {
                        await MainActor.run {
                            onTap()
                        }
                    } else if tapCount >= 2 {
                        await MainActor.run {
                            onDoubleTap()
                        }
                    }
                    tapCount = 0
                }
            }
        }
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isSelected)
    }

    private var cardBackground: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.06)
        : Color.black.opacity(0.04)
    }

    private var cardBorder: Color {
        colorScheme == .dark
        ? Color.white.opacity(0.10)
        : Color.black.opacity(0.08)
    }
}

// MARK: - Models

private struct SmartList: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let count: Int
    let color: Color
}

// MARK: - Reminder Row

private struct ReminderRow: View {
    let reminder: ReminderItem
    let onToggleComplete: () -> Void
    let onSelect: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var tagStore: TagStore
    
    var body: some View {
        HStack(spacing: 12) {
            Button {
                onToggleComplete()
            } label: {
                Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(reminder.isCompleted ? .green : .secondary)
                    .font(.system(size: 20))
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: reminder.isCompleted)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title)
                    .foregroundStyle(reminder.isCompleted ? .secondary : .primary)
                    .strikethrough(reminder.isCompleted)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: reminder.isCompleted)
                
                if let dueDate = reminder.dueDate {
                    Text(formatDate(dueDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let reminderIdentifier = reminder.ekReminder?.calendarItemIdentifier {
                    let tags = tagStore.getTags(forReminderIdentifier: reminderIdentifier)
                    TagPillRow(tags: tags)
                } else {
                    let tags = tagStore.getTags(for: reminder.id)
                    TagPillRow(tags: tags)
                }
            }
            
            Spacer()
            
            if reminder.priority != .none {
                Circle()
                    .fill(reminder.priority.color)
                    .frame(width: 8, height: 8)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .onTapGesture {
            onSelect()
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        DateHelper.applySettings(formatter)
        return formatter.string(from: date)
    }
}

// MARK: - Create Reminder View

private struct CreateReminderView: View {
    let onDismiss: () -> Void
    
    @StateObject private var eventKitService = EventKitService.shared
    @State private var title: String = ""
    @State private var dueDate: Date?
    @State private var hasDueDate: Bool = false
    @State private var errorMessage: String? = nil
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                }
                
                Section {
                    Toggle("Due Date", isOn: $hasDueDate)
                    
                    if hasDueDate {
                        DatePicker("Date & Time", selection: Binding(
                            get: { dueDate ?? Date() },
                            set: { dueDate = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                    }
                }
            }
            .navigationTitle("New Reminder")
            #if os(iOS)
.navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createReminder()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
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
        }
    }
    
    private func createReminder() {
        Task {
            do {
                _ = try await eventKitService.createReminder(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    dueDate: hasDueDate ? dueDate : nil
                )
                onDismiss()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Reminder Edit View

private struct ReminderEditView: View {
    @State private var title: String
    @State private var dueDate: Date?
    @State private var hasDueDate: Bool
    @State private var location: String
    @State private var showDeleteConfirmation = false
    @State private var showLocationSearch = false
    @State private var showAddTagSheet = false
    @State private var editingTag: Tag?
    let originalReminder: ReminderItem
    let eventKitService: EventKitService
    let onSave: (ReminderItem) -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    
    @EnvironmentObject private var tagStore: TagStore
    @Environment(\.colorScheme) private var colorScheme
    
    private var tagTargetId: UUID {
        if let identifier = originalReminder.ekReminder?.calendarItemIdentifier {
            return TagStore.stableUUID(for: identifier)
        }
        return originalReminder.id
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
    
    init(reminder: ReminderItem, eventKitService: EventKitService, onSave: @escaping (ReminderItem) -> Void, onCancel: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self._title = State(initialValue: reminder.title)
        self._dueDate = State(initialValue: reminder.dueDate)
        self._hasDueDate = State(initialValue: reminder.dueDate != nil)
        let locationName = reminder.ekReminder?.alarms?.compactMap { $0.structuredLocation?.title }.first ?? ""
        self._location = State(initialValue: locationName)
        self.originalReminder = reminder
        self.eventKitService = eventKitService
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                }
                
                Section {
                    Toggle("Due Date", isOn: $hasDueDate)
                    
                    if hasDueDate {
                        DatePicker("Date & Time", selection: Binding(
                            get: { dueDate ?? Date() },
                            set: { dueDate = $0 }
                        ), displayedComponents: [.date, .hourAndMinute])
                    }
                }
                
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
            .navigationTitle("Edit Reminder")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .confirmationDialog("Delete Reminder", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    onDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this reminder? This action cannot be undone.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveReminder()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
    
    private func saveReminder() {
        guard let ekReminder = originalReminder.ekReminder else {
            return
        }
        
        ekReminder.title = title
        
        // Update due date
        if hasDueDate, let dueDate = dueDate {
            // Remove existing date alarms
            ekReminder.alarms?.removeAll { $0.absoluteDate != nil }
            let alarm = EKAlarm(absoluteDate: dueDate)
            ekReminder.addAlarm(alarm)
        } else {
            // Remove date alarms if due date is disabled
            ekReminder.alarms?.removeAll { $0.absoluteDate != nil }
        }
        
        // Update location
        // Remove existing location alarms
        ekReminder.alarms?.removeAll { $0.structuredLocation != nil }
        
        if !location.isEmpty {
            let structuredLocation = EKStructuredLocation(title: location)
            let locationAlarm = EKAlarm()
            locationAlarm.structuredLocation = structuredLocation
            locationAlarm.proximity = .enter
            ekReminder.addAlarm(locationAlarm)
        }
        
        do {
            try eventKitService.saveReminder(ekReminder)
            
            let updatedReminder = ReminderItem(
                id: originalReminder.id,
                ekReminder: ekReminder,
                title: title,
                isCompleted: originalReminder.isCompleted,
                priority: originalReminder.priority,
                dueDate: hasDueDate ? dueDate : nil
            )
            onSave(updatedReminder)
        } catch {
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
}

// MARK: - Reminder Search View

private struct ReminderSearchView: View {
        @Environment(\.dismiss) private var dismiss
        var onSelect: (ReminderItem) -> Void
        @State private var searchText: String = ""
        @StateObject private var eventKitService = EventKitService.shared
        @State private var cachedReminders: [ReminderItem] = []
        @State private var isLoading = false
        
        private let minSearchLength = 2
        
        var body: some View {
            NavigationStack {
#if os(iOS)
                Group {
                    if searchText.isEmpty {
                        ContentUnavailableView("Search Reminders", systemImage: "magnifyingglass", description: Text("Enter at least \(minSearchLength) characters to search"))
                    } else if searchText.count < minSearchLength {
                        ContentUnavailableView("Search Reminders", systemImage: "magnifyingglass", description: Text("Enter at least \(minSearchLength) characters"))
                    } else if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filteredReminders.isEmpty {
                        ContentUnavailableView("No Results", systemImage: "magnifyingglass", description: Text("No reminders found"))
                    } else {
                        List {
                            ForEach(filteredReminders) { reminder in
                                ReminderRow(
                                    reminder: reminder,
                                    onToggleComplete: {},
                                    onSelect: {
                                        onSelect(reminder)
                                        dismiss()
                                    }
                                )
                            }
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search reminders")
                .navigationTitle("Search")
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
                .task {
                    await loadRemindersCache()
                }
#else
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Search reminders", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                    
                    if searchText.isEmpty {
                        Text("Enter at least \(minSearchLength) characters to search")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else if searchText.count < minSearchLength {
                        Text("Enter at least \(minSearchLength) characters")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if !searchText.isEmpty {
                        List {
                            ForEach(filteredReminders) { reminder in
                                ReminderRow(
                                    reminder: reminder,
                                    onToggleComplete: {},
                                    onSelect: {
                                        onSelect(reminder)
                                        dismiss()
                                    }
                                )
                            }
                        }
                        .listStyle(.plain)
                    }
                }
                .padding()
                .navigationTitle("Search")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .task {
                    await loadRemindersCache()
                }
#endif
            }
        }
        
        private var filteredReminders: [ReminderItem] {
            guard searchText.count >= minSearchLength else { return [] }
            let query = searchText.lowercased()
            return cachedReminders.filter { reminder in
                reminder.title.lowercased().contains(query)
            }
        }
        
        private func loadRemindersCache() async {
            guard cachedReminders.isEmpty else { return }
            
            await MainActor.run {
                isLoading = true
            }
            
            let ekReminders = await eventKitService.getReminders(includeCompleted: true)
            
            let reminders = ekReminders.map { ekReminder in
                let dueDate = ekReminder.alarms?.first?.absoluteDate
                // Use stable ID from calendarItemIdentifier
                return ReminderItem(
                    id: ReminderItem.stableId(from: ekReminder),
                    ekReminder: ekReminder,
                    title: ekReminder.title,
                    isCompleted: ekReminder.isCompleted,
                    priority: priorityFromEK(ekReminder.priority),
                    dueDate: dueDate
                )
            }
            
            await MainActor.run {
                cachedReminders = reminders
                isLoading = false
            }
        }
        
        private func priorityFromEK(_ priority: Int) -> ReminderPriority {
            switch priority {
            case 1: return .high
            case 5: return .medium
            case 9: return .low
            default: return .none
            }
        }
    }

// MARK: - Reminder Edit Sheet Wrapper

@MainActor
struct ReminderEditSheetWrapper: View {
    let reminder: ReminderItem
    let eventKitService: EventKitService
    let onDismiss: () -> Void
    let onRequestDelete: (ReminderItem) -> Void
    
    @EnvironmentObject private var tagStore: TagStore
    
    var body: some View {
        ReminderEditView(
            reminder: reminder,
            eventKitService: eventKitService,
            onSave: { _ in
                onDismiss()
            },
            onCancel: {
                onDismiss()
            },
            onDelete: {
                onRequestDelete(reminder)
            }
        )
        .environmentObject(tagStore)
    }
}

@MainActor
struct RemindersView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            RemindersView()
                .navigationTitle("Reminders")
        }
        .environmentObject(TagStore.shared)
    }
}
