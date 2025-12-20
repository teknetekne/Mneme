import SwiftUI

/// Balance chart showing income/expense per day
struct BalanceChartView: View {
    @State private var dataPoints: [ChartDataPoint] = []
    @State private var selectedDate: Date?
    @State private var isLoading = true
    @StateObject private var currencySettings = CurrencySettingsStore.shared
    
    private let dataProvider = ChartDataProvider.shared
    
    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if dataPoints.isEmpty {
                emptyStateView
            } else {
                HealthStyleChart(
                    dataPoints: dataPoints,
                    chartType: .balance,
                    accentColor: .green,
                    secondaryColor: .mint,
                    selectedDate: $selectedDate
                )
                .overlay(alignment: .topTrailing) {
                    currencyBadge
                }
            }
        }
        .task {
            await loadData()
        }
    }
    
    private var currencyBadge: some View {
        Text(currencySettings.baseCurrency)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(.ultraThinMaterial))
            .padding(16)
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
    
    private func loadData() async {
        let data = await dataProvider.getBalanceData(period: .day)
        await MainActor.run {
            self.dataPoints = data
            self.isLoading = false
        }
    }
}

#Preview {
    BalanceChartView()
        .padding()
}
