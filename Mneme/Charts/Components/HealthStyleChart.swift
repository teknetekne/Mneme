import SwiftUI
import Charts

/// Apple Health-style bar chart with scrolling and selection
struct HealthStyleChart: View {
    let dataPoints: [ChartDataPoint]
    let chartType: ChartType
    let accentColor: Color
    let secondaryColor: Color
    let timePeriod: ChartTimePeriod
    
    @Binding var selectedDate: Date?
    @State private var scrollPosition: Date = Date()
    
    @Environment(\.colorScheme) private var colorScheme
    
    private let barWidth: CGFloat = 28
    
    init(
        dataPoints: [ChartDataPoint],
        chartType: ChartType,
        accentColor: Color = .blue,
        secondaryColor: Color = .blue.opacity(0.6),
        timePeriod: ChartTimePeriod = .day,
        selectedDate: Binding<Date?>
    ) {
        self.dataPoints = dataPoints
        self.chartType = chartType
        self.accentColor = accentColor
        self.secondaryColor = secondaryColor
        self.timePeriod = timePeriod
        self._selectedDate = selectedDate
    }
    
    /// Number of data points to show based on period
    private var visibleItems: Int {
        switch timePeriod {
        case .day: return 14
        case .week: return 12
        case .month: return 12
        }
    }
    
    /// Visible domain length in seconds
    private var visibleDomainLength: Int {
        switch timePeriod {
        case .day: return 3600 * 24 * 14         // 14 days visible
        case .week: return 3600 * 24 * 7 * 12    // 12 weeks visible
        case .month: return 3600 * 24 * 30 * 12  // 12 months visible
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with title and summary
            headerView
            
            // Chart container
            chartContainer
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
    
    // MARK: - Header
    
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: chartType.systemImage)
                    .foregroundStyle(accentColor)
                    .font(.system(size: 16, weight: .semibold))
                
                Text(chartType.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                // Period indicator
                Text(timePeriod.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
            
            if let selected = selectedDate, let point = dataPoints.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }) {
                selectedValueView(point)
            } else {
                summaryView
            }
        }
    }
    
    private func selectedValueView(_ point: ChartDataPoint) -> some View {
        HStack(spacing: 4) {
            Text(formattedValue(point.value))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(accentColor)
            
            Text(chartType.unit)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(formatDateForPeriod(point.date))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.ultraThinMaterial))
        }
        .transition(.opacity)
    }
    
    private var summaryView: some View {
        let average = ChartDataProvider.shared.average(of: dataPoints)
        let total = ChartDataProvider.shared.total(of: dataPoints)
        
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Average")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formattedValue(average))
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            
            if chartType != .balance {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(formattedValue(total))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - Chart
    
    private var chartContainer: some View {
        Chart(dataPoints) { point in
            BarMark(
                x: .value("Date", point.date, unit: calendarUnit),
                y: .value("Value", point.value)
            )
            .foregroundStyle(barGradient(for: point))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .opacity(isSelected(point) ? 1.0 : 0.7)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: strideComponent, count: strideCount)) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel {
                        Text(formatAxisLabel(date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                    .foregroundStyle(.secondary.opacity(0.3))
                AxisValueLabel {
                    if let doubleValue = value.as(Double.self) {
                        Text(compactValue(doubleValue))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleDomainLength)
        .chartScrollPosition(x: $scrollPosition)
        .chartXSelection(value: $selectedDate)
        .chartPlotStyle { plotArea in
            plotArea
                .background(.clear)
        }
        .frame(height: 200)
        .animation(.easeInOut(duration: 0.2), value: selectedDate)
    }
    
    // MARK: - Period-based helpers
    
    private var calendarUnit: Calendar.Component {
        switch timePeriod {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }
    
    private var strideComponent: Calendar.Component {
        switch timePeriod {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }
    
    private var strideCount: Int {
        switch timePeriod {
        case .day: return 2    // Every 2 days
        case .week: return 2   // Every 2 weeks
        case .month: return 2  // Every 2 months
        }
    }
    
    private func formatAxisLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch timePeriod {
        case .day:
            formatter.dateFormat = "d"  // Just day number
        case .week:
            formatter.dateFormat = "d/M" // Day/Month
        case .month:
            formatter.dateFormat = "MMM" // Short month
        }
        return formatter.string(from: date)
    }
    
    private func formatDateForPeriod(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch timePeriod {
        case .day:
            formatter.dateFormat = "d MMM"
        case .week:
            formatter.dateFormat = "MMM d"
        case .month:
            formatter.dateFormat = "MMMM yyyy"
        }
        DateHelper.applyDateFormat(formatter)
        return formatter.string(from: date)
    }
    
    // MARK: - Helpers
    
    private func barGradient(for point: ChartDataPoint) -> LinearGradient {
        let colors: [Color]
        if chartType == .balance || chartType == .calories {
            colors = point.value >= 0 
                ? [accentColor, secondaryColor]
                : [.red, .red.opacity(0.6)]
        } else {
            colors = [accentColor, secondaryColor]
        }
        
        return LinearGradient(
            colors: colors,
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    private func isSelected(_ point: ChartDataPoint) -> Bool {
        guard let selected = selectedDate else { return true }
        return Calendar.current.isDate(point.date, inSameDayAs: selected)
    }
    
    private func formattedValue(_ value: Double) -> String {
        switch chartType {
        case .productivity:
            return value.clean(maxDecimals: 1)
        case .calories:
            let sign = value >= 0 ? "+" : ""
            return "\(sign)\(value.clean(maxDecimals: 0))"
        case .balance:
            let sign = value >= 0 ? "+" : ""
            return "\(sign)\(value.clean(maxDecimals: 2))"
        }
    }
    
    private func compactValue(_ value: Double) -> String {
        if abs(value) >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        return value.clean(maxDecimals: 0)
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
}

#Preview {
    ScrollView {
        HealthStyleChart(
            dataPoints: [
                ChartDataPoint(date: Date().addingTimeInterval(-86400 * 6), value: 5.5),
                ChartDataPoint(date: Date().addingTimeInterval(-86400 * 5), value: 7.2),
                ChartDataPoint(date: Date().addingTimeInterval(-86400 * 4), value: 4.0),
                ChartDataPoint(date: Date().addingTimeInterval(-86400 * 3), value: 8.0),
                ChartDataPoint(date: Date().addingTimeInterval(-86400 * 2), value: 6.5),
                ChartDataPoint(date: Date().addingTimeInterval(-86400 * 1), value: 3.2),
                ChartDataPoint(date: Date(), value: 5.0),
            ],
            chartType: .productivity,
            accentColor: .blue,
            timePeriod: .day,
            selectedDate: .constant(nil)
        )
        .padding()
    }
}
