import SwiftUI

/// Calories chart showing net calorie intake per day
struct CaloriesChartView: View {
    @State private var dataPoints: [ChartDataPoint] = []
    @State private var selectedDate: Date?
    @State private var isLoading = true
    
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
                    chartType: .calories,
                    accentColor: .orange,
                    secondaryColor: .yellow,
                    selectedDate: $selectedDate
                )
            }
        }
        .task {
            await loadData()
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading calorie data...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(height: 280)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "flame")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No Calorie Data")
                .font(.headline)
            Text("Log meals and activities to see your calorie trends.")
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
        let data = await dataProvider.getCaloriesData(period: .day)
        await MainActor.run {
            self.dataPoints = data
            self.isLoading = false
        }
    }
}

#Preview {
    CaloriesChartView()
        .padding()
}
