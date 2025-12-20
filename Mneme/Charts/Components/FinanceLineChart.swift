import SwiftUI
import Charts

/// Apple Finance-style line chart with gradient area
struct FinanceLineChart: View {
    let dataPoints: [ChartDataPoint]
    let title: String
    let icon: String
    let accentColor: Color
    let timePeriod: ChartTimePeriod
    let valueFormatter: (Double) -> String
    
    @Binding var selectedDate: Date?
    @State private var scrollPosition: Date = Date()
    
    @Environment(\.colorScheme) private var colorScheme
    
    init(
        dataPoints: [ChartDataPoint],
        title: String,
        icon: String,
        accentColor: Color,
        timePeriod: ChartTimePeriod = .day,
        valueFormatter: @escaping (Double) -> String = { String(format: "%.2f", $0) },
        selectedDate: Binding<Date?>
    ) {
        self.dataPoints = dataPoints
        self.title = title
        self.icon = icon
        self.accentColor = accentColor
        self.timePeriod = timePeriod
        self.valueFormatter = valueFormatter
        self._selectedDate = selectedDate
    }
    
    /// Visible domain length in seconds
    private var visibleDomainLength: Int {
        switch timePeriod {
        case .day: return 3600 * 24 * 30        // 30 days visible
        case .week: return 3600 * 24 * 7 * 12   // 12 weeks visible
        case .month: return 3600 * 24 * 30 * 12 // 12 months visible
        }
    }
    
    private var lineColor: Color {
        if let lastPoint = dataPoints.last {
            return lastPoint.value >= 0 ? accentColor : .red
        }
        return accentColor
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
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
                Image(systemName: icon)
                    .foregroundStyle(accentColor)
                    .font(.system(size: 16, weight: .semibold))
                
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                Text(timePeriod.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.ultraThinMaterial))
            }
            
            if let selected = selectedDate, let point = findPoint(for: selected) {
                selectedValueView(point)
            } else {
                currentValueView
            }
        }
    }
    
    private func findPoint(for date: Date) -> ChartDataPoint? {
        dataPoints.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }
    
    private func selectedValueView(_ point: ChartDataPoint) -> some View {
        HStack(spacing: 4) {
            Text(valueFormatter(point.value))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(point.value >= 0 ? accentColor : .red)
            
            Spacer()
            
            Text(formatDate(point.date))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.ultraThinMaterial))
        }
    }
    
    private var currentValueView: some View {
        let total = dataPoints.reduce(0) { $0 + $1.value }
        let average = dataPoints.isEmpty ? 0 : total / Double(dataPoints.count)
        
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Current")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(valueFormatter(dataPoints.last?.value ?? 0))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle((dataPoints.last?.value ?? 0) >= 0 ? accentColor : .red)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Average")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(valueFormatter(average))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Chart
    
    private var chartContainer: some View {
        Chart(dataPoints) { point in
            // Area fill
            AreaMark(
                x: .value("Date", point.date, unit: calendarUnit),
                y: .value("Value", point.value)
            )
            .foregroundStyle(areaGradient)
            .interpolationMethod(.catmullRom)
            
            // Line on top
            LineMark(
                x: .value("Date", point.date, unit: calendarUnit),
                y: .value("Value", point.value)
            )
            .foregroundStyle(lineColor)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.catmullRom)
            
            // Selection point
            if let selected = selectedDate, Calendar.current.isDate(point.date, inSameDayAs: selected) {
                PointMark(
                    x: .value("Date", point.date, unit: calendarUnit),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(.white)
                .symbolSize(80)
                
                PointMark(
                    x: .value("Date", point.date, unit: calendarUnit),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(lineColor)
                .symbolSize(50)
            }
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
            plotArea.background(.clear)
        }
        .frame(height: 200)
        .animation(.easeInOut(duration: 0.2), value: selectedDate)
    }
    
    // MARK: - Styling
    
    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [
                lineColor.opacity(0.3),
                lineColor.opacity(0.1),
                lineColor.opacity(0.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // MARK: - Period helpers
    
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
        case .day: return 5    // Show label every 5 days
        case .week: return 3   // Show label every 3 weeks
        case .month: return 2  // Show label every 2 months
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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = timePeriod.detailDateFormat
        DateHelper.applyDateFormat(formatter)
        return formatter.string(from: date)
    }
    
    private func compactValue(_ value: Double) -> String {
        if abs(value) >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        return String(format: "%.0f", value)
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
        FinanceLineChart(
            dataPoints: (0..<30).map { i in
                ChartDataPoint(
                    date: Date().addingTimeInterval(-Double(29 - i) * 86400),
                    value: Double.random(in: -500...1000)
                )
            },
            title: "Balance",
            icon: "dollarsign.circle.fill",
            accentColor: .green,
            timePeriod: .day,
            valueFormatter: { value in
                let sign = value >= 0 ? "+" : ""
                return String(format: "%@%.2f", sign, value)
            },
            selectedDate: .constant(nil)
        )
        .padding()
    }
}
