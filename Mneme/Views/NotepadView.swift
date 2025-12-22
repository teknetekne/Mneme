import SwiftUI
import Foundation
import MapKit
#if os(iOS)
import UIKit
#endif


struct NotepadView: View {
    @StateObject private var viewModel = NotepadViewModel()
    
    var body: some View {
        NotepadContent(viewModel: viewModel, lineStore: viewModel.lineStore)
    }
}

struct NotepadContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var viewModel: NotepadViewModel
    @ObservedObject var lineStore: LineStore
    
    private var backgroundColor: Color { Color.appBackground(colorScheme: colorScheme) }
    #if os(iOS)
    private var editorUIFont: UIFont { UIFont.preferredFont(forTextStyle: .body) }
    #endif
    
    @State private var showVariableDialog: Bool = false
    @State private var showActiveWorkMenu: Bool = false
    @State private var newWorkProjectName: String = ""
    @StateObject private var variableStore = VariableStore.shared
    @StateObject private var workSessionStore = WorkSessionStore.shared
    @FocusState private var focusedLineId: UUID?
    
    @State private var showAddTagSheet = false
    @State private var currentTagEventId: UUID?
    @State private var currentTagInitialName = ""
    @State private var tagBeingEdited: Tag?
    @State private var isLocationSearchActive = false
    @State private var locationSearchLineId: UUID?
    @State private var previousFocusedLineId: UUID?
    @StateObject private var locationSearchService = LocationSearchService()
    @FocusState private var isLocationSearchFocused: Bool
    @State private var suppressedParsingLineIds: Set<UUID> = []
    @State private var textUpdateTasks: [UUID: Task<Void, Never>] = [:]
    
    // Mood Emoji Picker
    @State private var showMoodPicker = false
    @State private var moodPickerLineId: UUID?
    
    // MARK: - Init
    // Implicit memberwise init is sufficient for ObservedObjects passed from parent
    
    // MARK: - Computed Properties
    
    private var reminderEvents: [(id: UUID, type: String, subject: String, displayName: String, day: String?, time: String?)] {
        viewModel.reminderEvents
    }
    
    private var hasReminderOrEvent: Bool {
        viewModel.hasReminderOrEvent
    }
    
    private var firstActiveLineId: UUID? {
        lineStore.lineOrder.first { id in
            lineStore.linesById[id]?.isActive == true
        }
    }
    
    private var isAnyModalPresented: Bool {
        showVariableDialog || showActiveWorkMenu || showAddTagSheet || tagBeingEdited != nil
    }


    var body: some View {
        mainContent
            .onAppear {
                viewModel.warmupServices()
                viewModel.validateExistingLines()
                DispatchQueue.main.async {
                    focusFirstLine()
                }
            }
            .onReceive(lineStore.$focusedId) { newValue in
                // Prevent focus stealing when modals are presented
                guard !showVariableDialog && !showActiveWorkMenu && !showAddTagSheet && tagBeingEdited == nil else { return }
                guard focusedLineId != newValue else { return }
                focusedLineId = newValue
            }
    }
    
    // MARK: - Main Content
    
    private var mainContent: some View {
        applyConditionalModifiers(to: contentZStack)
    }
    
    private var contentZStack: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()
            linesScrollView
            if viewModel.showSnackbar { snackbarView }
        }
        .overlay(alignment: .bottomTrailing) {
            keyboardDismissButton
        }
    }

    private var linesScrollView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(lineStore.lineOrder, id: \.self) { lineId in
                    if let line = lineStore.linesById[lineId], line.isActive {
                        LineRowView(
                            line: line,
                            lineStore: lineStore,
                            viewModel: viewModel,
                            editorUIFont: editorUIFont,
                            focusedLineId: $focusedLineId,
                            isLocationSearchActive: $isLocationSearchActive,
                            locationSearchLineId: $locationSearchLineId,
                            previousFocusedLineId: $previousFocusedLineId,
                            isLocationSearchFocused: $isLocationSearchFocused,
                            locationSearchService: locationSearchService,
                            isModalPresented: isAnyModalPresented,
                            showMoodPicker: $showMoodPicker,
                            moodPickerLineId: $moodPickerLineId,
                            onMoodSelected: { emoji in
                                selectMoodEmoji(emoji)
                            },
                            onReturn: {
                                handleReturnKey(for: lineId)
                            },
                            onEmptyBackspace: {
                                handleEmptyBackspace(for: lineId)
                            },
                            onTextChanged: { oldText, newText in
                                handleTextInputChange(for: lineId, oldText: oldText, newText: newText)
                            }
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
    


    // MARK: - Line Input Handling
    
    private func focusFirstLine() {
        if let firstActive = firstActiveLineId {
            focusedLineId = firstActive
        }
    }
    
    private func handleReturnKey(for lineId: UUID) {
        let targetId = lineStore.activateNextLineAtEnd() ?? lineStore.addLine(after: lineId)
        DispatchQueue.main.async {
            focusedLineId = targetId
        }
    }
    
    private func handleEmptyBackspace(for lineId: UUID) {
        if let prevLineId = lineStore.deactivateLine(lineId) {
            DispatchQueue.main.async {
                focusedLineId = prevLineId
            }
        }
    }
    
    private func handleTextInputChange(for lineId: UUID, oldText: String, newText: String) {
        guard oldText != newText else { return }
        
        // Detect ":" for mood picker
        if newText == ":" {
            moodPickerLineId = lineId
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showMoodPicker = true
            }
            return
        } else if showMoodPicker && moodPickerLineId == lineId {
            // Dismiss if text changes from ":" to something else
            withAnimation(.easeInOut(duration: 0.2)) {
                showMoodPicker = false
            }
            moodPickerLineId = nil
        }
        
        if newText.hasSuffix("@") && !oldText.hasSuffix("@") {
            // @ character is intercepted in shouldChangeTextIn, so it never gets added to UITextView
            // But we receive it in callback to trigger location search
            locationSearchLineId = lineId
            previousFocusedLineId = focusedLineId ?? lineStore.focusedId
            focusedLineId = nil
            lineStore.focusedId = nil
            withAnimation(.easeInOut(duration: 0.2)) {
                isLocationSearchActive = true
            }
            locationSearchService.searchQuery = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isLocationSearchFocused = true
            }
        } else if let atIndex = newText.lastIndex(of: "@"), isLocationSearchActive && locationSearchLineId == lineId {
            // Remove @ and everything before it, keep only text after @
            let afterAt = String(newText[newText.index(after: atIndex)...])
            let textBeforeAt = String(newText[..<atIndex])
            lineStore.updateText(for: lineId, newText: textBeforeAt)
            locationSearchService.searchQuery = afterAt
        } else if !newText.contains("@") && isLocationSearchActive && locationSearchLineId == lineId {
            withAnimation(.easeInOut(duration: 0.2)) {
                isLocationSearchActive = false
            }
            locationSearchService.reset()
            isLocationSearchFocused = false
            locationSearchLineId = nil
            restorePreviousFocus()
        }
        
        if newText.contains("\n") && newText.components(separatedBy: .newlines).count > 1 {
            let parts = newText.components(separatedBy: .newlines).filter { !$0.isEmpty }
            if let firstPart = parts.first {
                lineStore.updateText(for: lineId, newText: firstPart)
                if oldText != firstPart {
                    viewModel.handleTextChange(for: lineId, oldValue: oldText, newValue: firstPart)
                }
            }
            
            var lastCreatedId = lineId
            for part in parts.dropFirst() {
                let newId = lineStore.addLine(after: lastCreatedId)
                lineStore.updateText(for: newId, newText: part)
                if !part.isEmpty {
                    viewModel.handleTextChange(for: newId, oldValue: "", newValue: part)
                }
                lastCreatedId = newId
            }
            
            DispatchQueue.main.async {
                focusedLineId = lastCreatedId
            }
            return
        }
        
        let isDeletion = newText.count < oldText.count
        let debounceDelay: UInt64 = isDeletion ? 10_000_000 : 50_000_000
        
        textUpdateTasks[lineId]?.cancel()
        textUpdateTasks[lineId] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: debounceDelay)
            
            guard !Task.isCancelled else { return }
            
            let currentText = lineStore.linesById[lineId]?.text ?? ""
            guard currentText == newText || currentText == oldText else { return }
            
            lineStore.updateText(for: lineId, newText: newText)
            viewModel.handleTextChange(for: lineId, oldValue: oldText, newValue: newText)
            
            textUpdateTasks.removeValue(forKey: lineId)
        }
    }

    // MARK: - Keyboard Dismiss Button
    
    @ViewBuilder
    private var keyboardDismissButton: some View {
        #if os(iOS)
        if lineStore.focusedId != nil {
            Button {
                focusedLineId = nil
                lineStore.focusedId = nil
            } label: {
                Image(systemName: "keyboard.chevron.compact.down")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.orange)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
        #endif
    }
    
    // MARK: - Modifiers
    
    @ViewBuilder
    private func applyConditionalModifiers<Content: View>(to content: Content) -> some View {
        #if os(iOS)
        content.safeAreaInset(edge: .bottom) {
            if hasReminderOrEvent {
                reminderEventToolbar
            }
        }
        .sheet(isPresented: $showAddTagSheet) {
            AddTagSheet(
                eventId: currentTagEventId ?? UUID(),
                initialName: currentTagInitialName,
                onSave: { name, colorName in
                    if let eventId = currentTagEventId {
                        viewModel.addTag(lineId: eventId, tag: name, colorName: colorName)
                    }
                    showAddTagSheet = false
                },
                onCancel: {
                    showAddTagSheet = false
                }
            )
        }
        .sheet(item: $tagBeingEdited) { tag in
            EditTagSheet(
                eventId: currentTagEventId ?? tag.id,
                tagId: tag.id,
                currentTag: tag.name,
                currentColorName: tag.colorName,
                onSave: { oldTag, newTag, colorName in
                    viewModel.updateTagInDatabase(oldName: oldTag, newName: newTag, colorName: colorName)
                    tagBeingEdited = nil
                },
                onCancel: {
                    tagBeingEdited = nil
                }
            )
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 12) {
                    Button { showVariableDialog = true } label: { 
                        Image(systemName: "plus")
                    }
                    
                    Button {
                        showActiveWorkMenu.toggle()
                    } label: {
                        Image(systemName: "briefcase.fill")
                            .foregroundStyle(.primary)
                    }
                }
            }
                ToolbarItem(placement: .confirmationAction) {
                    Group {
                        #if os(iOS)
                        Button("Done", systemImage: "checkmark", role: .confirm) {
                            finishEditing()
                        }
                        #else
                        Button {
                            finishEditing()
                        } label: {
                            Label("Done", systemImage: "checkmark")
                        }
                        #endif
                    }
                    .tint(.orange)
                    .disabled(!viewModel.allLinesParsedSuccessfully)
                }
        }
        .sheet(isPresented: $showVariableDialog) {
            VariableDialogView(isPresented: $showVariableDialog, variableStore: variableStore)
        }
        .sheet(isPresented: $showActiveWorkMenu) {
            activeWorkSessionSheet
        }
        .alert("Active Work Session", isPresented: $viewModel.showWorkSessionConfirmation) {
            Button("Cancel", role: .cancel) {
                viewModel.pendingWorkStart = nil
                viewModel.existingWorkSession = nil
            }
            Button("Replace", role: .destructive) {
                viewModel.confirmWorkStartReplacement()
                let calendar = Calendar.current
                if let pending = viewModel.pendingWorkStart, calendar.isDate(pending.date, inSameDayAs: Date()) {
                    newWorkProjectName = ""
                }
            }
        } message: {
            if let existing = viewModel.existingWorkSession {
                let calendar = Calendar.current
                let dateFormatter = DateFormatter()
                if calendar.isDate(existing.date, inSameDayAs: Date()) {
                    dateFormatter.dateStyle = .none
                    dateFormatter.timeStyle = .none
                    let objectStr = existing.object != nil ? " (\(existing.object!))" : ""
                    return Text("An active work session exists from today at \(formatStoredTime(existing.startTime))\(objectStr). Starting a new session will replace it.")
                } else {
                    dateFormatter.dateStyle = .medium
                    dateFormatter.timeStyle = .none
                    let dateStr = dateFormatter.string(from: existing.date)
                    let objectStr = existing.object != nil ? " (\(existing.object!))" : ""
                    return Text("An active work session exists from \(dateStr) at \(formatStoredTime(existing.startTime))\(objectStr). Starting a new session will replace it.")
                }
            } else {
                return Text("An active work session exists. Starting a new session will replace it.")
            }
        }
        #else
        content
        #endif
    }

    // MARK: - Snackbar
    private var snackbarView: some View {
        VStack { 
            Spacer()
            SnackbarView(
                title: viewModel.snackbarTitle,
                message: viewModel.snackbarMessage,
                style: viewModel.snackbarType == .success ? .success : .error,
                onDismiss: {
                    withAnimation {
                        viewModel.showSnackbar = false
                    }
                }
            )
            .padding(.bottom, lineStore.focusedId != nil ? 80 : 20)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.3), value: viewModel.showSnackbar)
        .zIndex(100)
    }

    // MARK: - Active Work Session Sheet
    
    private var activeWorkSessionSheet: some View {
        NavigationStack {
            Form {
                if let activeSession = workSessionStore.getActiveWorkSession() {
                    Section {
                        if let object = activeSession.object {
                            HStack {
                                Text("Project")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(object)
                            }
                        }
                        
                        HStack {
                            Text("Started")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatStoredTime(activeSession.startTime))
                        }
                        
                        HStack {
                            Text("Duration")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(DateHelper.calculateElapsedTime(from: activeSession.startTime))
                        }
                        
                        Button(role: .destructive) {
                            endActiveWorkSession()
                            showActiveWorkMenu = false
                        } label: {
                            HStack {
                                Spacer()
                                Text("End Work Session")
                                Spacer()
                            }
                        }
                    }
                } else {
                    Section {
                        TextField("Project name (optional)", text: $newWorkProjectName)
                            #if os(iOS)
.textInputAutocapitalization(.never)
#endif
                            .autocorrectionDisabled()
                    }
                    
                    Section {
                        Button {
                            startNewWorkSession()
                            showActiveWorkMenu = false
                        } label: {
                            HStack {
                                Spacer()
                                Text("Start Work")
                                Spacer()
                            }
                        }
                        .disabled(false)
                    }
                }
            }
            .navigationTitle("Work Session")
            #if os(iOS)
.navigationBarTitleDisplayMode(.inline)
#endif
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }
    
    private func startNewWorkSession() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        let currentTime = formatter.string(from: Date())
        
        let projectName = newWorkProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let object = projectName.isEmpty ? nil : projectName
        
        let result = workSessionStore.recordWorkStart(date: Date(), time: currentTime, object: object)
        switch result {
        case .success:
            viewModel.showSnack("Work started at \(currentTime)" + (object != nil ? " - \(object!)" : ""))
            newWorkProjectName = ""
        case .needsConfirmation(let existingSession):
            viewModel.pendingWorkStart = (date: Date(), time: currentTime, object: object)
            viewModel.existingWorkSession = existingSession
            viewModel.showWorkSessionConfirmation = true
        }
    }
    
    private func endActiveWorkSession() {
        guard let activeSession = workSessionStore.getActiveWorkSession() else {
            viewModel.showSnack("No active work session found")
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        let currentTime = formatter.string(from: Date())
        
        let calendar = Calendar.current
        let sessionDate = calendar.startOfDay(for: activeSession.date)
        
        let components = currentTime.split(separator: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else {
            viewModel.showSnack("Invalid time format")
            return
        }
        
        guard let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: sessionDate) else {
            viewModel.showSnack("Invalid date")
            return
        }
        
        if let session = workSessionStore.recordWorkEnd(date: date, time: currentTime, object: activeSession.object),
           let duration = session.durationMinutes {
            let hours = duration / 60
            let minutes = duration % 60
            let durationText = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
            let objectText = session.object != nil ? " (\(session.object!))" : ""
            viewModel.showSnack("Work ended. Duration: \(durationText)\(objectText)")
        } else {
            viewModel.showSnack("Failed to end work session")
        }
    }
    
    // MARK: - Variable Dialog
    

    
    // MARK: - Reminder/Event Toolbar
    
    private var reminderEventToolbar: some View {
        VStack(spacing: 4) {
            ForEach(reminderEvents, id: \.id) { event in
                ReminderEventToolbar(
                    eventId: event.id,
                    displayName: event.displayName,
                    type: event.type,
                    day: event.day,
                    time: event.time,
                    tags: viewModel.getTagObjects(for: event.id),
                    unaddedTags: viewModel.getUnaddedTags(for: event.id),
                    onAddTag: { tagName in
                        viewModel.addTag(lineId: event.id, tag: tagName, colorName: nil)
                    },
                    onRemoveTag: { tag in
                        viewModel.removeTag(lineId: event.id, tag: tag.name)
                    },
                    onAddNewTag: {
                        currentTagEventId = event.id
                        currentTagInitialName = ""
                        showAddTagSheet = true
                    },
                    onEditTag: { tag in
                        tagBeingEdited = tag
                    },
                    onDeleteTag: { tag in
                        viewModel.deleteTag(tag.name)
                    },
                    onAddLocation: {
                        locationSearchLineId = event.id
                        previousFocusedLineId = focusedLineId ?? lineStore.focusedId
                        focusedLineId = nil
                        lineStore.focusedId = nil
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLocationSearchActive = true
                        }
                        locationSearchService.searchQuery = ""
                        // Focus on search field after animation
        // Focus on search field after animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            isLocationSearchFocused = true
                        }
                    }
                )
            }
        }
        .padding(.vertical, 4)
    }
    
    private func finishEditing() {
        // Dismiss keyboard and hide dismiss button
        focusedLineId = nil
        lineStore.focusedId = nil
        
        Task {
            await viewModel.processLines()
        }
    }
    
    // MARK: - Helper Views
    

    
    // MARK: - Mood Selection
    
    private func selectMoodEmoji(_ emoji: String) {
        guard let lineId = moodPickerLineId else { return }
        
        let currentText = lineStore.linesById[lineId]?.text ?? ""
        
        focusedLineId = nil
        lineStore.focusedId = nil
        
        withAnimation(.easeInOut(duration: 0.2)) {
            showMoodPicker = false
        }
        moodPickerLineId = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let newText = currentText + emoji + " "
            self.lineStore.updateText(for: lineId, newText: newText)
            
            DispatchQueue.main.async {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.focusedLineId = lineId
                    self.lineStore.focus(lineId)
                }
            }
        }
    }



    private func restorePreviousFocus() {
        if let previousId = previousFocusedLineId {
            focusedLineId = previousId
            lineStore.focus(previousId)
            previousFocusedLineId = nil
        }
    }

    private func formatStoredTime(_ time: String) -> String {
        let components = time.split(separator: ":")
        guard components.count == 2,
              let hour = Int(components[0]),
              let minute = Int(components[1]) else {
            return time
        }
        
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        
        let now = Date()
        guard let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else {
            return time
        }
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        DateHelper.applyTimeFormat(formatter)
        return formatter.string(from: date)
    }
}

#Preview("Light") {
    NavigationStack { NotepadView() }
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack { NotepadView() }
        .preferredColorScheme(.dark)
}
