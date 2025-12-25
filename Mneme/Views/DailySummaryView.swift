import SwiftUI
import EventKit

enum SummaryTab: String, CaseIterable, Identifiable {
    case overview
    case productivity
    case calories
    case balance
    case mood
    case analysis
    
    var id: Self { self }
    
    /// Returns available tabs based on platform
    /// macOS excludes chart tabs due to compatibility issues
    static var availableCases: [SummaryTab] {
        return allCases.map { $0 }
    }
    
    var title: String {
        switch self {
        case .overview: return "Overview"
        case .productivity: return "Productivity"
        case .calories: return "Calories"
        case .balance: return "Balance"
        case .mood: return "Mood"
        case .analysis: return "Analysis"
        }
    }
    
    var systemImage: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .productivity: return "briefcase.fill"
        case .calories: return "flame.fill"
        case .balance: return "dollarsign.circle.fill"
        case .mood: return "face.smiling.fill"
        case .analysis: return "sparkle.magnifyingglass"
        }
    }
    
    var tintColor: Color {
        switch self {
        case .overview: return .purple
        case .productivity: return .blue
        case .calories: return .orange
        case .balance: return .green
        case .mood: return .pink
        case .analysis: return .indigo
        }
    }
}


struct ManageEntriesConfig: Identifiable {
    let id = UUID()
    let date: Date
}

struct DailySummaryView: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var workSessionStore = WorkSessionStore.shared
    @StateObject private var notepadEntryStore = NotepadEntryStore.shared
    @StateObject private var eventKitService = EventKitService.shared
    @StateObject private var healthKitService = HealthKitService.shared
    @StateObject private var currencySettingsStore = CurrencySettingsStore.shared

    private var backgroundColor: Color {
        Color.appBackground(colorScheme: colorScheme)
    }

    @State private var selectedTab: SummaryTab = .overview
    @State private var expanded: Set<Date> = []
    @State private var summaries: [DailySummary] = []
    @State private var showDatePicker = false
    @State private var searchDate = Date()
    @State private var showSettings = false
    @State private var loadingTask: Task<Void, Never>?
    @State private var debounceTask: Task<Void, Never>?
    @State private var isLoading = false
    @State private var loadedDays = 0
    @State private var manageEntriesConfig: ManageEntriesConfig?

    private let horizontalInset: CGFloat = 16
    private let cardCorner: CGFloat = 14
    private let cardShadowRadius: CGFloat = 6

    var body: some View {
        #if os(iOS)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    tabBar
                    contentBody(proxy: proxy)
                }
            }
        }
        .background(backgroundColor.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            if selectedTab == .overview {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showDatePicker = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerView(
                selectedDate: $searchDate,
                onDateSelected: { date in
                    searchDate = date
                    selectedTab = .overview
                    // We need a small delay to ensure we're on the overview tab before scrolling
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NotificationCenter.default.post(name: NSNotification.Name("ScrollToSummaryDate"), object: date)
                    }
                    showDatePicker = false
                }
            )
            .presentationDetents([.height(500), .large])
            .presentationDragIndicator(.visible)
        }
        #else
        VStack(spacing: 0) {
            tabBar
            contentBody
        }
        #endif
    }
    

    
    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(SummaryTab.availableCases) { tab in
                    Button {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .medium))
                            Text(tab.title)
                                .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(selectedTab == tab ? tab.tintColor : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            Group {
                                if selectedTab == tab {
                                    Capsule()
                                        .fill(tab.tintColor.opacity(0.15))
                                        .overlay(
                                            Capsule()
                                                .stroke(tab.tintColor.opacity(0.3), lineWidth: 1)
                                        )
                                }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(backgroundColor)
    }
    private func contentBody(proxy: ScrollViewProxy) -> some View {
        Group {
                switch selectedTab {
                case .overview:
                    OverviewChartTab(proxy: proxy)
                case .productivity:
                    ProductivityTab()
                case .calories:
                    CaloriesTab()
                case .balance:
                    BalanceTab()
                case .mood:
                    MoodTab()
                case .analysis:
                    AnalysisTab()
                }
            }
            .animation(.easeInOut(duration: 0.3), value: selectedTab)
    }
    
    private func overviewContent(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            summaryList
        }
        .navigationTitle("Daily Summary")
        .toolbarBackground(backgroundColor, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showDatePicker = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
            }
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerView(
                selectedDate: $searchDate,
                onDateSelected: { date in
                    searchDate = date
                    scrollToDate(date, proxy: proxy)
                    showDatePicker = false
                }
            )
            .presentationDetents([.height(500), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            loadSummaries()
        }
        .onChange(of: workSessionStore.sessions) { _, _ in
            debounceLoadSummaries()
        }
        .onChange(of: notepadEntryStore.entries) { _, _ in
            debounceLoadSummaries()
        }
        .onDisappear {
            loadingTask?.cancel()
            debounceTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notepadEntryDeleted)) { _ in
            loadSummaries()
        }
        .sheet(item: $manageEntriesConfig) { config in
            ManageEntriesView(date: config.date)
        }
    }
    
    private func debounceLoadSummaries() {
        // Cancel previous debounce task
        debounceTask?.cancel()
        
        // Create new debounced task
        debounceTask = Task {
            // Wait 0.5 seconds
            try? await Task.sleep(nanoseconds: 500_000_000)
            
            // Check if cancelled
            guard !Task.isCancelled else { return }
            
            // Load summaries
            loadSummaries()
        }
    }
    
    private var summaryList: some View {
        LazyVStack(spacing: 12) {
            if summaries.isEmpty && isLoading {
                ProgressView()
                    .padding()
            } else {
            ForEach(summaries, id: \.id) { summary in
                DailySummaryCard(
                    summary: summary,
                    isExpanded: expanded.contains(summary.id),
                    toggle: { toggle(summary.id) },
                    onManageEntries: { date in
                        manageEntriesConfig = ManageEntriesConfig(date: date)
                    },
                    cornerRadius: cardCorner,
                    shadowRadius: cardShadowRadius
                )
                .id(summary.id)
                }
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    

    
    private func loadSummaries() {
        // Cancel previous task if still running
        loadingTask?.cancel()
        
        isLoading = true
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var newSummaries: [DailySummary] = []
        
        loadingTask = Task { @MainActor in
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            // Load first 7 days immediately, then load rest lazily
            let initialDays = min(7, 30)
            
            for dayOffset in 0..<initialDays {
                // Check cancellation periodically
                if Task.isCancelled { return }
                
                guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
                
                if let summary = await loadSummaryForDate(date) {
                    newSummaries.append(summary)
                }
            }
            
            // Update UI with initial batch
            if !Task.isCancelled {
                summaries = newSummaries.sorted { $0.date > $1.date }
                loadedDays = initialDays
                isLoading = false
            }
            
            // Load remaining days in background
            if initialDays < 30 && !Task.isCancelled {
                var remainingSummaries: [DailySummary] = []
                
                for dayOffset in initialDays..<30 {
                    if Task.isCancelled { break }
                    
                    guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
                    
                    if let summary = await loadSummaryForDate(date) {
                        remainingSummaries.append(summary)
                    }
                    
                    // Update every 5 days to show progress
                    if (dayOffset - initialDays) % 5 == 0 && !Task.isCancelled {
                        await MainActor.run {
                            summaries = (newSummaries + remainingSummaries).sorted { $0.date > $1.date }
                            loadedDays = dayOffset + 1
                        }
                    }
                }
                
                // Final update
                if !Task.isCancelled {
                    await MainActor.run {
                        summaries = (newSummaries + remainingSummaries).sorted { $0.date > $1.date }
                        loadedDays = 30
                        isLoading = false
                    }
                }
            }
        }
    }
    
    private func loadSummaryForDate(_ date: Date) async -> DailySummary? {
        guard !Task.isCancelled else { return nil }
        
        let calendar = Calendar.current
                let dayStart = calendar.startOfDay(for: date)
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
                
                // Work sessions
                let workData = workSessionStore.getTotalWorkDuration(for: date)
                
                // Calculate total calories from meal and calorie_adjustment entries
                let dayEntries = notepadEntryStore.getEntries(for: date)
                var totalCalories: Double = 0.0
        
        // First, add meal calories (synchronous)
                for entry in dayEntries {
                    if let kcal = entry.mealKcal {
                        totalCalories += kcal
                    }
                }
                
        // Activity calories are already stored as negative values in mealKcal
        // Only use entries that have mealKcal - ignore legacy entries without calories
        
        // Add HealthKit active energy burned (negative because we burned calories)
        if healthKitService.isAuthorized && !Task.isCancelled {
                    if let activeEnergy = await healthKitService.getActiveEnergyBurned(for: date) {
                totalCalories -= activeEnergy
                    }
                }
                
                // Calculate daily net change (income - expense) for this day only
                let currencyService = CurrencyService.shared
                let baseCurrency = currencySettingsStore.baseCurrency
                var dailyNetChange: Double = 0.0
                var balanceByCurrency: [String: Double] = [:]
                
                for entry in dayEntries {
            if Task.isCancelled { break }
            
                    if (entry.intent == "income" || entry.intent == "expense"),
                       let amount = entry.amount,
                       let currency = entry.currency {
                        // Income is positive, expense is negative
                        let signedAmount = entry.intent == "expense" ? -amount : amount
                        
                        // Convert to base currency
                if !Task.isCancelled {
                        if let convertedAmount = await currencyService.convertAmount(abs(amount), from: currency, to: baseCurrency) {
                            dailyNetChange += (entry.intent == "expense" ? -convertedAmount : convertedAmount)
                        } else {
                            // If conversion fails, keep original amount
                            dailyNetChange += signedAmount
                    }
                        }
                        
                        // Track by currency (always positive for display)
                        balanceByCurrency[currency, default: 0.0] += signedAmount
                    }
                }
                
                // EventKit reminders and events
                var remindersCompleted = 0
                var eventsCount = 0
                
        if eventKitService.isAuthorized && !Task.isCancelled {
                    let reminders = await eventKitService.getReminders(includeCompleted: true)
            if !Task.isCancelled {
                    remindersCompleted = reminders.filter { reminder in
                        guard let completionDate = reminder.completionDate else { return false }
                        return calendar.isDate(completionDate, inSameDayAs: date)
                    }.count
                    
                    let events = eventKitService.getEvents(startDate: dayStart, endDate: dayEnd)
                    eventsCount = events.count
            }
                }
                
                // Extract journal entries (mood + journal text)
                var moodEmoji: String? = nil
                var journalText: String? = nil
                
                for entry in dayEntries {
                    if entry.intent == "journal" {
                        // Extract mood emoji from start of originalText
                        let moodEmojis = ["😢", "😕", "😐", "🙂", "😊"]
                        for emoji in moodEmojis {
                            if entry.originalText.hasPrefix(emoji) {
                                moodEmoji = emoji
                                let remaining = String(entry.originalText.dropFirst(emoji.count)).trimmingCharacters(in: .whitespaces)
                                if !remaining.isEmpty {
                                    journalText = remaining
                                }
                                break
                            }
                        }
                        
                        // If no emoji found but entry exists, check object field for journal text
                        if moodEmoji == nil {
                            if let objectText = entry.object, !objectText.isEmpty {
                                journalText = objectText
                            } else {
                                // Fallback: use originalText if no emoji and no object
                                let trimmed = entry.originalText.trimmingCharacters(in: .whitespaces)
                                if !trimmed.isEmpty {
                                    journalText = trimmed
                                }
                            }
                        } else if journalText == nil {
                            // Emoji found but no text after emoji, check object field
                            if let objectText = entry.object, !objectText.isEmpty {
                                journalText = objectText
                            }
                        }
                        
                        // Only take first journal entry per day
                        break
                    }
                }
                
                let summary = DailySummary(
                    date: date,
                    remindersCompleted: remindersCompleted,
                    eventsCount: eventsCount,
                    moodEmoji: moodEmoji,
                    journalText: journalText,
                    workDurationMinutes: workData?.minutes,
                    workObject: workData?.object,
                    totalCalories: totalCalories != 0 ? totalCalories : nil,
                    balance: dailyNetChange != 0 ? dailyNetChange : nil,
                    balanceByCurrency: balanceByCurrency.isEmpty ? nil : balanceByCurrency,
                    baseCurrency: baseCurrency
                )
                
                if summary.remindersCompleted > 0 || 
                   summary.eventsCount > 0 || 
                   summary.moodEmoji != nil ||
                   summary.journalText != nil ||
                   summary.workDurationMinutes != nil ||
                   summary.totalCalories != nil ||
                   summary.balance != nil {
            return summary
        }
        
        return nil
    }
    
    private func calculateActivityCalories(for entry: ParsedNotepadEntry) async -> Double {
        let activityParserService = ActivityParserService.shared
        
        // Parse activity from original text
        guard let activityResult = await activityParserService.parseActivity(from: entry.originalText) else {
            return 0.0
        }
        
        return activityResult.caloriesBurned
    }

    private func toggle(_ id: Date) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            if expanded.contains(id) {
                expanded.remove(id)
            } else {
                expanded.insert(id)
            }
        }
    }
    
    private func scrollToDate(_ date: Date, proxy: ScrollViewProxy) {
        let targetDate = calendar.startOfDay(for: date)
        if let summary = summaries.first(where: { calendar.isDate($0.date, inSameDayAs: targetDate) }) {
            withAnimation {
                proxy.scrollTo(summary.id, anchor: .top)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if !expanded.contains(summary.id) {
                    toggle(summary.id)
                }
            }
        }
    }
}

// MARK: - Card


// MARK: - Date Picker View

private struct DatePickerView: View {
    @Binding var selectedDate: Date
    let onDateSelected: (Date) -> Void
    
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    
    @State private var currentMonth: Date = Date()
    @State private var previousSelectedDate: Date? = nil
    
    private let horizontalInset: CGFloat = 16
    private let gridSpacing: CGFloat = 8
    private let headerTitleFont: Font = .title3.bold()
    private let weekdayFont: Font = .caption.bold()
    
    init(selectedDate: Binding<Date>, onDateSelected: @escaping (Date) -> Void) {
        self._selectedDate = selectedDate
        self.onDateSelected = onDateSelected
        let now = selectedDate.wrappedValue
        if let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now)) {
            _currentMonth = State(initialValue: start)
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, horizontalInset)
                        .padding(.top, 12)
                        .padding(.bottom, 10)
                    
                    weekdayHeader
                        .padding(.horizontal, horizontalInset)
                    
                    DatePickerMonthGridView(
                        monthStart: currentMonth,
                        selectedDate: $selectedDate,
                        previousSelectedDate: previousSelectedDate,
                        calendar: calendar,
                        horizontalInset: horizontalInset,
                        gridSpacing: gridSpacing,
                        onDateSelected: { date in
                            previousSelectedDate = selectedDate
                            selectedDate = date
                        }
                    )
                    
                    Button {
                        onDateSelected(selectedDate)
                    } label: {
                        Text("Search")
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .padding(.horizontal, horizontalInset)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    
                }
            }
            .navigationTitle("Search Date")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if !calendar.isDate(selectedDate, equalTo: currentMonth, toGranularity: .month) {
                    if let start = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate)) {
                        currentMonth = start
                    }
                }
            }
        }
    }
    
    private var header: some View {
        HStack(spacing: 0) {
            Text(monthTitle(for: currentMonth))
                .font(headerTitleFont)
                .foregroundStyle(.primary)
            
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
        }
    }
    
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
        .padding(.top, 8)
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
    
    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    
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
}

// MARK: - Date Picker Month Grid

private struct DatePickerMonthGridView: View {
    let monthStart: Date
    @Binding var selectedDate: Date
    let previousSelectedDate: Date?
    let calendar: Calendar
    let horizontalInset: CGFloat
    let gridSpacing: CGFloat
    let onDateSelected: (Date) -> Void

    private let gridCellHeight: CGFloat = 44

    private var days: [DatePickerDateValue] {
        let range = calendar.range(of: .day, in: .month, for: monthStart) ?? 1..<31
        let firstWeekdayOfMonth = calendar.component(.weekday, from: monthStart)
        let firstWeekdayIndex = calendar.firstWeekday
        let leadingEmpty = ((firstWeekdayOfMonth - firstWeekdayIndex) + 7) % 7

        var items: [DatePickerDateValue] = []
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
                        DatePickerDayCell(
                            date: date,
                            isToday: calendar.isDateInToday(date),
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isPreviousSelected: previousSelectedDate != nil && calendar.isDate(date, inSameDayAs: previousSelectedDate!),
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
            .padding(.bottom, 8)
        }
    }
}

private enum DatePickerDateValue: Equatable {
    case placeholder
    case day(Date)
}

// MARK: - Date Picker Day Cell

private struct DatePickerDayCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let isPreviousSelected: Bool
    let selectedDate: Date
    let calendar: Calendar

    private let dayNumberFont: Font = .subheadline.weight(.medium)
    private let minRowHeight: CGFloat = 44
    private let daySize: CGFloat = 36

    var body: some View {
        VStack(spacing: 4) {
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

            Spacer()
                .frame(height: 3)
        }
        .frame(maxWidth: .infinity, minHeight: minRowHeight)
        .padding(.vertical, 4)
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

#Preview {
    NavigationStack {
        DailySummaryView()
    }
}

