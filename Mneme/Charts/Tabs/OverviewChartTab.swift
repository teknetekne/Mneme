import SwiftUI

/// Overview tab showing Today + This Week summaries + Daily expandable cards
struct OverviewChartTab: View {
    let proxy: ScrollViewProxy
    
    @State private var productivityData: [ChartDataPoint] = []
    @State private var caloriesData: [ChartDataPoint] = []
    @State private var balanceData: [ChartDataPoint] = []
    @State private var summaries: [DailySummary] = []
    @State private var expanded: Set<Date> = []
    @State private var isLoading = true
    @State private var loadingTask: Task<Void, Never>?
    @State private var pendingScrollDate: Date? = nil
    @State private var manageEntriesConfig: ManageEntriesConfig?
    
    @StateObject private var workSessionStore = WorkSessionStore.shared
    @StateObject private var notepadEntryStore = NotepadEntryStore.shared
    @StateObject private var eventKitService = EventKitService.shared
    @StateObject private var healthKitService = HealthKitService.shared
    @StateObject private var currencySettingsStore = CurrencySettingsStore.shared
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.calendar) private var calendar
    
    private let dataProvider = ChartDataProvider.shared
    
    var body: some View {
        VStack(spacing: 20) {
            if isLoading {
                loadingView
            } else {
                todaySummaryCards
                weeklyHighlights
                dailySummarySection
            }
        }
        .padding(16)
        .task {
            await loadAllData()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ScrollToSummaryDate"))) { notification in
            if let date = notification.object as? Date {
                scrollToDate(date)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notepadEntryDeleted)) { _ in
            Task {
                await loadAllData()
            }
        }
        .sheet(item: $manageEntriesConfig) { config in
            ManageEntriesView(date: config.date)
        }
    }

    private func scrollToDate(_ date: Date) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = "date-\(formatter.string(from: date))"
        let targetDate = calendar.startOfDay(for: date)
        
        // If still loading, capture for later
        if isLoading {
            pendingScrollDate = date
            return
        }
        
        // Find if we have a summary for this date
        if let summary = summaries.first(where: { calendar.isDate($0.date, inSameDayAs: targetDate) }) {
            // Use a slightly longer delay to ensure the view has rendered after isLoading = false
            // and the statistics cards are fully laid out.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                    // Scroll to the card by its String ID
                    proxy.scrollTo(dateString, anchor: .top)
                }
                
                // Auto-expand the matched summary with an additional delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if !expanded.contains(summary.id) {
                        toggleExpanded(summary.id)
                    }
                }
            }
        }
    }
    
    // MARK: - Loading
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading overview...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Today Summary
    
    private var todaySummaryCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                summaryCard(
                    title: "Work",
                    value: todayWorkHours,
                    unit: "hours",
                    icon: "briefcase.fill",
                    color: .blue
                )
                
                summaryCard(
                    title: "Calories",
                    value: todayCalories,
                    unit: "kcal",
                    icon: "flame.fill",
                    color: .orange
                )
                
                summaryCard(
                    title: "Balance",
                    value: todayBalance,
                    unit: "",
                    icon: "dollarsign.circle.fill",
                    color: todayBalanceValue >= 0 ? .green : .red,
                    showSign: true
                )
            }
        }
    }
    
    private func summaryCard(
        title: String,
        value: String,
        unit: String,
        icon: String,
        color: Color,
        showSign: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(cardBorder, lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: shadowColor, radius: 6, x: 0, y: 2)
    }
    
    // MARK: - Weekly Highlights
    
    private var weeklyHighlights: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            
            VStack(spacing: 12) {
                highlightRow(
                    title: "Total Work",
                    value: "\(weeklyWorkTotal.clean(maxDecimals: 1)) hours",
                    subtitle: "Avg: \(weeklyWorkAverage.clean(maxDecimals: 1)) hrs/day",
                    icon: "briefcase.fill",
                    color: .blue
                )
                
                Divider()
                
                highlightRow(
                    title: "Net Calories",
                    value: "\(weeklyCaloriesTotal.clean(maxDecimals: 0)) kcal",
                    subtitle: "Avg: \(weeklyCaloriesAverage.clean(maxDecimals: 0)) kcal/day",
                    icon: "flame.fill",
                    color: .orange
                )
                
                Divider()
                
                highlightRow(
                    title: "Net Balance",
                    value: formatBalance(weeklyBalanceTotal),
                    subtitle: "Avg: \(formatBalance(weeklyBalanceAverage))/day",
                    icon: "dollarsign.circle.fill",
                    color: weeklyBalanceTotal >= 0 ? .green : .red
                )
            }
            .padding(16)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(cardBorder, lineWidth: 0.8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: shadowColor, radius: 6, x: 0, y: 2)
        }
    }
    
    private func highlightRow(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        color: Color
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
    }
    
    // MARK: - Daily Summary Section
    
    private var dailySummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily History")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            
            LazyVStack(spacing: 12) {
                let formatter: DateFormatter = {
                    let df = DateFormatter()
                    df.dateFormat = "yyyy-MM-dd"
                    return df
                }()
                
                ForEach(summaries, id: \.id) { summary in
                    let dateString = "date-\(formatter.string(from: summary.date))"
                    
                    DailySummaryCard(
                        summary: summary,
                        isExpanded: expanded.contains(summary.id),
                        toggle: { toggleExpanded(summary.id) },
                        onManageEntries: { date in
                            manageEntriesConfig = ManageEntriesConfig(date: date)
                        },
                        cornerRadius: 14,
                        shadowRadius: 6
                    )
                    .id(dateString)
                }
            }
        }
    }
    
    private func toggleExpanded(_ id: Date) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            if expanded.contains(id) {
                expanded.remove(id)
            } else {
                expanded.insert(id)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var cardBackground: some ShapeStyle {
        colorScheme == .dark 
            ? AnyShapeStyle(Color.white.opacity(0.06))
            : AnyShapeStyle(Color.black.opacity(0.04))
    }
    
    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }
    
    private var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.2) : .black.opacity(0.08)
    }
    
    private var todayWorkHours: String {
        if let today = productivityData.last {
            return today.value.clean(maxDecimals: 1)
        }
        return "0"
    }
    
    private var todayCalories: String {
        if let today = caloriesData.last {
            return today.value.clean(maxDecimals: 0)
        }
        return "0"
    }
    
    private var todayBalanceValue: Double {
        balanceData.last?.value ?? 0
    }
    
    private var todayBalance: String {
        formatBalance(todayBalanceValue)
    }
    
    private var weeklyWorkTotal: Double {
        dataProvider.total(of: productivityData)
    }
    
    private var weeklyWorkAverage: Double {
        dataProvider.average(of: productivityData)
    }
    
    private var weeklyCaloriesTotal: Double {
        dataProvider.total(of: caloriesData)
    }
    
    private var weeklyCaloriesAverage: Double {
        dataProvider.average(of: caloriesData)
    }
    
    private var weeklyBalanceTotal: Double {
        dataProvider.total(of: balanceData)
    }
    
    private var weeklyBalanceAverage: Double {
        dataProvider.average(of: balanceData)
    }
    
    private func formatBalance(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""

        return "\(sign)\(value.clean(maxDecimals: 2))"
    }
    
    // MARK: - Data Loading
    
    private func loadAllData() async {
        // Load chart data
        let productivity = dataProvider.getProductivityData(period: .day)
        let calories = await dataProvider.getCaloriesData(period: .day)
        let balance = await dataProvider.getBalanceData(period: .day)
        
        // Load daily summaries
        let dailySummaries = await loadDailySummaries()
        
        await MainActor.run {
            self.productivityData = productivity
            self.caloriesData = calories
            self.balanceData = balance
            self.summaries = dailySummaries
            self.isLoading = false
            
            // If we have a pending scroll, execute it now that data is loaded
            if let date = pendingScrollDate {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.scrollToDate(date)
                    self.pendingScrollDate = nil
                }
            }
        }
    }
    
    private func loadDailySummaries() async -> [DailySummary] {
        let today = calendar.startOfDay(for: Date())
        var results: [DailySummary] = []
        
        for dayOffset in 0..<14 { // Last 14 days
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            
            if let summary = await loadSummaryForDate(date) {
                results.append(summary)
            }
        }
        
        return results.sorted { $0.date > $1.date }
    }
    
    private func loadSummaryForDate(_ date: Date) async -> DailySummary? {
        // Work sessions
        let workData = workSessionStore.getTotalWorkDuration(for: date)
        
        // Calculate total calories
        let dayEntries = notepadEntryStore.getEntries(for: date)
        var totalCalories: Double = 0.0
        
        for entry in dayEntries {
            if let kcal = entry.mealKcal {
                totalCalories += kcal
            }
        }
        
        // Subtract active energy from HealthKit
        if healthKitService.isAuthorized {
            if let activeEnergy = await healthKitService.getActiveEnergyBurned(for: date) {
                totalCalories -= activeEnergy
            }
        }
        
        // Calculate daily net balance
        let currencyService = CurrencyService.shared
        let baseCurrency = currencySettingsStore.baseCurrency
        var dailyNetChange: Double = 0.0
        var balanceByCurrency: [String: Double] = [:]
        
        for entry in dayEntries {
            if (entry.intent == "income" || entry.intent == "expense"),
               let amount = entry.amount,
               let currency = entry.currency {
                let signedAmount = entry.intent == "expense" ? -amount : amount
                
                if let convertedAmount = await currencyService.convertAmount(abs(amount), from: currency, to: baseCurrency) {
                    dailyNetChange += (entry.intent == "expense" ? -convertedAmount : convertedAmount)
                } else {
                    dailyNetChange += signedAmount
                }
                
                balanceByCurrency[currency, default: 0.0] += signedAmount
            }
        }
        
        // Extract journal and mood
        var moodEmoji: String? = nil
        var journalText: String? = nil
        
        for entry in dayEntries {
            if entry.intent == "journal" {
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
                
                if moodEmoji == nil {
                    if let objectText = entry.object, !objectText.isEmpty {
                        journalText = objectText
                    } else {
                        let trimmed = entry.originalText.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            journalText = trimmed
                        }
                    }
                } else if journalText == nil {
                    if let objectText = entry.object, !objectText.isEmpty {
                        journalText = objectText
                    }
                }
                break
            }
        }
        
        let summary = DailySummary(
            date: date,
            remindersCompleted: 0,
            eventsCount: 0,
            moodEmoji: moodEmoji,
            journalText: journalText,
            workDurationMinutes: workData?.minutes,
            workObject: workData?.object,
            totalCalories: totalCalories != 0 ? totalCalories : nil,
            balance: dailyNetChange != 0 ? dailyNetChange : nil,
            balanceByCurrency: balanceByCurrency.isEmpty ? nil : balanceByCurrency,
            baseCurrency: baseCurrency
        )
        
        // Only return if there's any content
        if summary.moodEmoji != nil ||
           summary.journalText != nil ||
           summary.workDurationMinutes != nil ||
           summary.totalCalories != nil ||
           summary.balance != nil {
            return summary
        }
        
        return nil
    }
}

// MARK: - Daily Summary Card


#Preview {
    NavigationStack {
        ScrollViewReader { proxy in
            OverviewChartTab(proxy: proxy)
                .navigationTitle("Overview")
        }
    }
}

