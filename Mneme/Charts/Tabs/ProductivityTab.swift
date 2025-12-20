import SwiftUI

/// Productivity tab with full chart and time period filter
struct ProductivityTab: View {
    @State private var timePeriod: ChartTimePeriod = .day
    @State private var dataPoints: [ChartDataPoint] = []
    @State private var selectedDate: Date?
    @State private var isLoading = true
    
    @Environment(\.colorScheme) private var colorScheme
    
    private let dataProvider = ChartDataProvider.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Time Period Picker
            HStack {
                TimePeriodPicker(selection: $timePeriod, accentColor: .blue)
                Spacer()
            }
            
            // Chart
            chartSection
            
            // Stats
            if !dataPoints.isEmpty {
                statsSection
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
                HealthStyleChart(
                    dataPoints: dataPoints,
                    chartType: .productivity,
                    accentColor: .blue,
                    secondaryColor: .cyan,
                    timePeriod: timePeriod,
                    selectedDate: $selectedDate
                )
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading productivity data...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(height: 280)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "briefcase")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No Work Data")
                .font(.headline)
            Text("Start tracking your work sessions to see productivity trends.")
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
                statCard(title: "Total", value: String(format: "%.1f hrs", dataProvider.total(of: dataPoints)))
                statCard(title: "Average", value: String(format: "%.1f hrs", dataProvider.average(of: dataPoints)))
                statCard(title: "Best", value: String(format: "%.1f hrs", dataProvider.max(of: dataPoints)))
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
        }
        .frame(maxWidth: .infinity)
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
        let data = dataProvider.getProductivityData(period: timePeriod)
        await MainActor.run {
            self.dataPoints = data
            self.isLoading = false
        }
    }
}

#Preview {
    NavigationStack {
        ProductivityTab()
            .navigationTitle("Productivity")
    }
}

