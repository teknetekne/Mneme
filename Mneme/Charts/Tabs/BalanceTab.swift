import SwiftUI

/// Balance tab with Apple Finance-style line chart
struct BalanceTab: View {
    @State private var timePeriod: ChartTimePeriod = .day
    @State private var dataPoints: [ChartDataPoint] = []
    @State private var selectedDate: Date?
    @State private var isLoading = true
    
    @StateObject private var currencySettings = CurrencySettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme
    
    private let dataProvider = ChartDataProvider.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Time Period Picker
            HStack {
                TimePeriodPicker(selection: $timePeriod, accentColor: .green)
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
                FinanceLineChart(
                    dataPoints: dataPoints,
                    title: "Balance",
                    icon: "dollarsign.circle.fill",
                    accentColor: .green,
                    timePeriod: timePeriod,
                    valueFormatter: { value in
                        let sign = value >= 0 ? "+" : ""
                        return String(format: "%@%.2f %@", sign, value, currencySettings.baseCurrency)
                    },
                    selectedDate: $selectedDate
                )
            }
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading balance data...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(height: 280)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No Financial Data")
                .font(.headline)
            Text("Log income and expenses to see your balance trends.")
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
            HStack {
                Text("Statistics")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text(currencySettings.baseCurrency)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                statCard(title: "Net Change", value: formatBalance(netChange))
                statCard(title: "Average", value: formatBalance(dataProvider.average(of: dataPoints)))
                statCard(title: "Highest", value: formatBalance(dataProvider.max(of: dataPoints)))
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
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var netChange: Double {
        dataPoints.reduce(0) { $0 + $1.value }
    }
    
    private func formatBalance(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return String(format: "%@%.2f", sign, value)
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
        let data = await dataProvider.getBalanceData(period: timePeriod)
        await MainActor.run {
            self.dataPoints = data
            self.isLoading = false
        }
    }
}

#Preview {
    NavigationStack {
        BalanceTab()
            .navigationTitle("Balance")
    }
}

