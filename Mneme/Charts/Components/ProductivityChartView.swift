import SwiftUI

/// Productivity chart showing work hours per day
struct ProductivityChartView: View {
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
                    chartType: .productivity,
                    accentColor: .blue,
                    secondaryColor: .cyan,
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
    
    private func loadData() async {
        let data = dataProvider.getProductivityData(period: .day)
        await MainActor.run {
            self.dataPoints = data
            self.isLoading = false
        }
    }
}

#Preview {
    ProductivityChartView()
        .padding()
}
