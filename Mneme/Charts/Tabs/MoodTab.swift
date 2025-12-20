import SwiftUI

/// Mood tab with Apple Finance-style line chart
struct MoodTab: View {
    @State private var timePeriod: ChartTimePeriod = .day
    @State private var dataPoints: [ChartDataPoint] = []
    @State private var selectedDate: Date?
    @State private var isLoading = true
    
    @Environment(\.colorScheme) private var colorScheme
    
    private let dataProvider = ChartDataProvider.shared
    
    private let moodEmojis: [Double: String] = [
        1.0: "😢",
        2.0: "😕",
        3.0: "😐",
        4.0: "🙂",
        5.0: "😊"
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            // Time Period Picker
            HStack {
                TimePeriodPicker(selection: $timePeriod, accentColor: .pink)
                Spacer()
            }
            
            // Chart
            chartSection
            
            // Stats
            if !dataPoints.isEmpty {
                statsSection
                moodLegend
            }
        }
        .padding(16)
        .task {
            await loadData()
        }
        .onChange(of: timePeriod) { _, _ in
            Task {
                await loadData()
            }
        }
    }
    
    // MARK: - Chart
    
    private var chartSection: some View {
        Group {
            if isLoading {
                loadingView
            } else if dataPoints.isEmpty {
                emptyStateView
            } else {
                FinanceLineChart(
                    dataPoints: dataPoints,
                    title: "Mood",
                    icon: "face.smiling.fill",
                    accentColor: .pink,
                    timePeriod: timePeriod,
                    valueFormatter: { value in
                        let emoji = moodEmojis[round(value)] ?? "😐"
                        return String(format: "%.1f %@", value, emoji)
                    },
                    selectedDate: $selectedDate
                )
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading mood data...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(height: 280)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "face.smiling")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No Mood Data")
                .font(.headline)
            Text("Log your mood in journal entries to track your emotional wellbeing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(height: 280)
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Stats
    
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
                .foregroundStyle(.primary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                statCard(title: "Average", value: formatMood(dataProvider.average(of: dataPoints)))
                statCard(title: "Best", value: formatMood(dataProvider.max(of: dataPoints)))
                statCard(title: "Logged", value: "\(dataPoints.count) \(timePeriod == .day ? "days" : timePeriod == .week ? "weeks" : "months")")
            }
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
    
    private var moodLegend: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mood Scale")
                .font(.headline)
                .foregroundStyle(.primary)
            
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { score in
                    VStack(spacing: 4) {
                        Text(moodEmojis[Double(score)] ?? "")
                            .font(.title2)
                        Text("\(score)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
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
    
    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func formatMood(_ value: Double) -> String {
        let emoji = moodEmojis[round(value)] ?? "😐"
        return String(format: "%.1f %@", value, emoji)
    }
    
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
    
    private func loadData() async {
        await MainActor.run { isLoading = true }
        let data = dataProvider.getMoodData(period: timePeriod)
        await MainActor.run {
            self.dataPoints = data
            self.isLoading = false
        }
    }
}

#Preview {
    NavigationStack {
        MoodTab()
            .navigationTitle("Mood")
    }
}

