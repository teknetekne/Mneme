import SwiftUI
import EventKit

struct CalendarView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        Color.appBackground(colorScheme: colorScheme)
    }

    @State private var currentMonth: Date = Date()
    @State private var selectedDate: Date = Date()
    @State private var previousSelectedDate: Date? = nil
@State private var eventsByDay: [Date: [CalendarEvent]] = [:]
    
    @State private var showSearch = false
    @StateObject private var eventKitService = EventKitService.shared
    @StateObject private var tagStore = TagStore.shared
    @State private var isLoading = false
    @State private var selectedEvent: CalendarEvent? = nil
    @State private var showCreateEvent = false

    init() {
        let now = Date()
        if let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now)) {
            _currentMonth = State(initialValue: start)
        }
    }

    private let horizontalInset: CGFloat = 8
    private let gridSpacing: CGFloat = 4
    private let weekdayFont: Font = .caption.bold()

    var body: some View {
        ZStack {
            backgroundColor
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 0) {
                header
                    .padding(.horizontal, horizontalInset)
                    .padding(.top, 4)
                    .padding(.bottom, 12)

                weekdayHeader
                    .padding(.horizontal, horizontalInset)

                MonthGridView(
                    monthStart: currentMonth,
                    selectedDate: $selectedDate,
                    previousSelectedDate: previousSelectedDate,
                    eventsByDay: eventsByDay,
                    calendar: calendar,
                    horizontalInset: horizontalInset,
                    gridSpacing: gridSpacing,
                    onDateSelected: { date in
                        previousSelectedDate = selectedDate
                        selectedDate = date
                    }
                )
                .gesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            if value.translation.width < -50 {
                                goToNextMonth()
                            } else if value.translation.width > 50 {
                                goToPreviousMonth()
                            }
                        }
                )

                Divider()
                    .padding(.horizontal, horizontalInset)
                    .padding(.top, 8)

                EventsListContainer(
                    date: selectedDate,
                    events: eventsByDay[calendar.startOfDay(for: selectedDate)] ?? [],
                    onEventTapped: { event in
                        selectedEvent = event
                    }
                )
                    .padding(.top, 12)
                    .padding(.horizontal, horizontalInset)
                    .padding(.bottom, 16)
                }
            }
            .onAppear {
                if !calendar.isDate(selectedDate, equalTo: currentMonth, toGranularity: .month) {
                    selectedDate = currentMonth
                }
                loadEvents()
            }
            .onChange(of: currentMonth) { _, _ in
                loadEvents()
            }
            .refreshable {
                await loadEventsAsync()
            }
            .sheet(item: $selectedEvent) { event in
                EventDetailSheet(
                    event: event,
                    onDismiss: { selectedEvent = nil },
                    onDataChanged: {
                        Task { await loadEventsAsync() }
                    }
                )
                .environmentObject(tagStore)
                .id(event.id)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSearch.toggle()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .sheet(isPresented: $showSearch) {
                        SearchView(onSelect: { date in
                            if let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) {
                                currentMonth = start
                            }
                            selectedDate = date
                            showSearch = false
                        })
                            .presentationDetents([.medium, .large])
                            .presentationDragIndicator(.visible)
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showCreateEvent = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .sheet(isPresented: $showCreateEvent) {
                        CreateEventView {
                            showCreateEvent = false
                            Task {
                                await loadEventsAsync()
                            }
                        }
                    }
                }
                
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 0) {
            Text(monthTitle(for: currentMonth))
                .font(.largeTitle.bold())
                .foregroundStyle(.primary)
                .padding(.leading, 12)
            
            Spacer()
            
            HStack(spacing: 8) {
                Button {
                    goToPreviousMonth()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .help("Previous Month")
                }
                .buttonStyle(.plain)
                
                Button {
                    goToNextMonth()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                        .help("Next Month")
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 6)
        }
    }

    private func jumpToToday() {
        let today = Date()
        selectedDate = today
        if !calendar.isDate(today, equalTo: currentMonth, toGranularity: .month) {
            if let start = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) {
                currentMonth = start
            }
        }
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }

    // MARK: - Weekday Header

    private var weekdayHeader: some View {
        let symbols = weekdaySymbols()
        let firstWeekday = calendar.firstWeekday
        return HStack(spacing: 0) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                let weekday = (firstWeekday - 1 + index) % 7 + 1
                let isWeekend = weekday == 1 || weekday == 7
                Text(symbol)
                    .font(weekdayFont)
                    .foregroundStyle(isWeekend ? .red : .secondary)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    private func weekdaySymbols() -> [String] {
        var symbols = calendar.veryShortStandaloneWeekdaySymbols
        let firstWeekdayIndex = calendar.firstWeekday - 1
        if firstWeekdayIndex > 0 {
            symbols = Array(symbols[firstWeekdayIndex...]) + Array(symbols[..<firstWeekdayIndex])
        }
        return symbols
    }

    // MARK: - Month navigation

    private func goToPreviousMonth() {
        if let prev = calendar.date(byAdding: .month, value: -1, to: currentMonth) {
            currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: prev)) ?? prev
        }
    }

    private func goToNextMonth() {
        if let next = calendar.date(byAdding: .month, value: 1, to: currentMonth) {
            currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: next)) ?? next
        }
    }
    
    // MARK: - Data Loading
    
    private func loadEvents() {
        guard eventKitService.isAuthorized else {
            Task {
                let authorized = await eventKitService.requestFullAccess()
                if authorized {
                    await loadEventsAsync()
                }
            }
            return
        }
        
        Task {
            await loadEventsAsync()
        }
    }
    
    private func loadEventsAsync() async {
        await MainActor.run {
            isLoading = true
        }
        
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) ?? currentMonth
        // Get the start of the next month, then subtract 1 second to include all events of the current month
        guard let nextMonthStart = calendar.date(byAdding: .month, value: 1, to: startOfMonth) else {
            await MainActor.run {
                isLoading = false
            }
            return
        }
        let endOfMonth = calendar.date(byAdding: .second, value: -1, to: nextMonthStart) ?? startOfMonth
        
        let ekEvents = eventKitService.getEvents(startDate: startOfMonth, endDate: endOfMonth)
        
        var eventsDict: [Date: [CalendarEvent]] = [:]
        for ekEvent in ekEvents {
            let dayStart = calendar.startOfDay(for: ekEvent.startDate)
            let timeString = formatTime(ekEvent.startDate)
            let event = CalendarEvent(
                title: ekEvent.title,
                time: timeString,
                startDate: ekEvent.startDate,
                eventIdentifier: ekEvent.eventIdentifier
            )
            
            if eventsDict[dayStart] == nil {
                eventsDict[dayStart] = []
            }
            eventsDict[dayStart]?.append(event)
        }
        
        await MainActor.run {
            eventsByDay = eventsDict
            isLoading = false
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        DateHelper.applyTimeFormat(formatter)
        return formatter.string(from: date)
    }

}

// MARK: - Search View

private struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    var onSelect: (Date) -> Void
    @State private var searchText: String = ""
    @StateObject private var eventKitService = EventKitService.shared
    @State private var cachedEvents: [CalendarEvent] = []
    @State private var isLoading = false
    
    private let minSearchLength = 2
    
    var body: some View {
        NavigationStack {
            Group {
                if searchText.isEmpty {
                    ContentUnavailableView("Search Events", systemImage: "magnifyingglass", description: Text("Enter at least \(minSearchLength) characters to search"))
                } else if searchText.count < minSearchLength {
                    ContentUnavailableView("Search Events", systemImage: "magnifyingglass", description: Text("Enter at least \(minSearchLength) characters"))
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredEvents.isEmpty {
                    ContentUnavailableView("No Results", systemImage: "magnifyingglass", description: Text("No events found"))
                } else {
                    List {
                        ForEach(filteredEvents, id: \.id) { event in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentColor)
                                    .frame(width: 3, height: 16)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .font(.body)
                                    Text(formatDateAndTime(event.startDate))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect(event.startDate)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search events")
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadEventsCache()
            }
        }
    }
    
    private var filteredEvents: [CalendarEvent] {
        guard searchText.count >= minSearchLength else { return [] }
        let query = searchText.lowercased()
        return cachedEvents.filter { event in
            event.title.lowercased().contains(query)
        }
    }
    
    private func formatDateAndTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        DateHelper.applySettings(formatter)
        return formatter.string(from: date)
    }
    
    private func loadEventsCache() async {
        guard cachedEvents.isEmpty else { return }
        
        await MainActor.run {
            isLoading = true
        }
        
        let startDate = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        let endDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        let ekEvents = eventKitService.getEvents(startDate: startDate, endDate: endDate)
        
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        DateHelper.applyTimeFormat(formatter)
        
        let events = ekEvents.map { ekEvent in
            let timeString = formatter.string(from: ekEvent.startDate)
        return CalendarEvent(title: ekEvent.title, time: timeString, startDate: ekEvent.startDate, eventIdentifier: ekEvent.eventIdentifier)
        }
        
        await MainActor.run {
            cachedEvents = events
            isLoading = false
        }
    }
    
}

// MARK: - Month Picker

private struct MonthPicker: View {
    @Binding var currentMonth: Date
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Month")
                .font(.headline)

            DatePicker(
                "",
                selection: Binding(
                    get: { currentMonth },
                    set: { newValue in
                        if let start = calendar.date(from: calendar.dateComponents([.year, .month], from: newValue)) {
                            currentMonth = start
                        } else {
                            currentMonth = newValue
                        }
                    }
                ),
                displayedComponents: [.date]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
        }
    }
}

// MARK: - Month Grid

private struct MonthGridView: View {
    let monthStart: Date
    @Binding var selectedDate: Date
    let previousSelectedDate: Date?
    let eventsByDay: [Date: [CalendarEvent]]
    let calendar: Calendar
    let horizontalInset: CGFloat
    let gridSpacing: CGFloat
    let onDateSelected: (Date) -> Void
    @EnvironmentObject private var tagStore: TagStore

    private let gridCellHeight: CGFloat = 36

    private var days: [DateValue] {
        let range = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<31
        let firstWeekdayOfMonth = calendar.component(.weekday, from: monthStart)
        let firstWeekdayIndex = calendar.firstWeekday
        let leadingEmpty = ((firstWeekdayOfMonth - firstWeekdayIndex) + 7) % 7

        var items: [DateValue] = []
        for _ in 0..<leadingEmpty { items.append(.placeholder) }
        for day in range {
            if let date = calendar.date(bySetting: .day, value: day, of: monthStart) {
                items.append(.day(date))
            }
        }
        let remainder = items.count % 7
        if remainder != 0 {
            for _ in 0..<(7 - remainder) { items.append(.placeholder) }
        }
        return items
    }

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: gridSpacing) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, value in
                    switch value {
                    case .placeholder:
                        Color.clear
                            .frame(height: gridCellHeight)
                    case .day(let date):
                        let dayStart = calendar.startOfDay(for: date)
                        let events = eventsByDay[dayStart] ?? []
                        let eventColors = eventColors(for: events)
                        DayCell(
                            date: date,
                            isToday: calendar.isDateInToday(date),
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isPreviousSelected: previousSelectedDate != nil && calendar.isDate(date, inSameDayAs: previousSelectedDate!),
                            events: events,
                            eventColors: eventColors,
                            selectedDate: selectedDate,
                            calendar: calendar
                        )
                        .onTapGesture {
                            onDateSelected(date)
                        }
                    }
                }
            }
            .padding(.horizontal, horizontalInset)
            .padding(.top, 2)
            .padding(.bottom, 4)
        }
    }
    
    private func eventColors(for events: [CalendarEvent]) -> [Color] {
        var colors: [Color] = []
        
        for event in events {
            let tags = tagStore.getTags(forEventIdentifier: event.eventIdentifier)
            if let firstTag = tags.first {
                colors.append(firstTag.color)
            } else {
                colors.append(.accentColor)
            }
        }
        return colors
    }
}

private enum DateValue: Equatable {
    case placeholder
    case day(Date)
}

// MARK: - Day Cell

private struct DayCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let isPreviousSelected: Bool
    let events: [CalendarEvent]
    let eventColors: [Color]
    let selectedDate: Date
    let calendar: Calendar

    private let dayNumberFont: Font = .caption.weight(.medium)
    private let minRowHeight: CGFloat = 36
    private let daySize: CGFloat = 32

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Color.red)
                        .frame(width: daySize, height: daySize)
                } else if isToday {
                    if calendar.isDateInToday(selectedDate) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: daySize, height: daySize)
                    } else {
                        Circle()
                            .fill(Color.red.opacity(0.2))
                            .frame(width: daySize, height: daySize)
                    }
                }
                
                Text(dayString)
                    .font(dayNumberFont)
                    .foregroundStyle(foregroundColor)
            }
            .frame(width: daySize, height: daySize)

            if !eventColors.isEmpty {
                HStack(spacing: 2) {
                    ForEach(Array(eventColors.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(color)
                            .frame(width: 3, height: 3)
                    }
                }
                .frame(height: 3)
            } else {
                Spacer()
                    .frame(height: 3)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minRowHeight)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var dayString: String {
        String(calendar.component(.day, from: date))
    }

    private var foregroundColor: Color {
        if isSelected {
            return .white
        } else if isToday {
            if calendar.isDateInToday(selectedDate) {
                return .white
            } else {
                return .primary
            }
        } else {
            return .primary
        }
    }

}

// MARK: - Events List

private struct EventsListContainer: View {
    let date: Date
    let events: [CalendarEvent]
    let onEventTapped: (CalendarEvent) -> Void
    @EnvironmentObject private var tagStore: TagStore

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 0) {
            if events.isEmpty {
                Text("No events")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(events) { event in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .frame(width: 3, height: 16)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title)
                                .font(.system(size: 16, weight: .medium))
                            if let time = event.time {
                                Text(time)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            
                            let tags = tagStore.getTags(forEventIdentifier: event.eventIdentifier)
                            TagPillRow(tags: tags)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onEventTapped(event)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        #else
        VStack(alignment: .leading, spacing: 0) {
            if events.isEmpty {
                Text("No events")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ForEach(events) { event in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .frame(width: 3, height: 16)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title)
                                .font(.system(size: 16, weight: .medium))
                            if let time = event.time {
                                Text(time)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            
                            let tags = tagStore.getTags(forEventIdentifier: event.eventIdentifier)
                            TagPillRow(tags: tags)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onEventTapped(event)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        #endif
    }
}

// MARK: - Create Event View

private struct CreateEventView: View {
    let onDismiss: () -> Void
    
    @StateObject private var eventKitService = EventKitService.shared
    @State private var title: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(3600)
    @State private var notes: String = ""
    @State private var errorMessage: String? = nil
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                }
                
                Section {
                    DatePicker("Start", selection: $startDate)
                    DatePicker("End", selection: $endDate)
                }
                
                Section {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Event")
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
                        createEvent()
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
    
    private func createEvent() {
        Task {
            do {
                _ = try await eventKitService.createEvent(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    startDate: startDate,
                    endDate: endDate,
                    notes: notes.isEmpty ? nil : notes
                )
                onDismiss()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Model


struct CalendarEvent: Identifiable, Equatable {
    var id: String { eventIdentifier }
    let title: String
    let time: String?
    let startDate: Date
    let eventIdentifier: String
}

@MainActor
struct CalendarView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CalendarView()
        }
        .environmentObject(TagStore.shared)
    }
}
