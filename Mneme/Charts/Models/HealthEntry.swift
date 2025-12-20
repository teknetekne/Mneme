import Foundation

// MARK: - HealthEntry
/// Base model for Apple Health data.
/// Represents raw data from HealthKit.
struct HealthEntry: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let value: Double
    
    init(id: UUID = UUID(), date: Date, value: Double) {
        self.id = id
        self.date = date
        self.value = value
    }
}

// MARK: - AggregatedEntry
/// Aggregated data point.
/// Created from DateBins or Dictionary(grouping:) results.
struct AggregatedEntry: Identifiable, Hashable {
    let id: UUID
    let binStart: Date       // Group start date
    let binEnd: Date         // Group end date
    let sum: Double          // Total value
    let count: Int           // Data count
    let entries: [HealthEntry] // Raw data (for optional detail)
    
    init(
        id: UUID = UUID(),
        binStart: Date,
        binEnd: Date,
        sum: Double,
        count: Int,
        entries: [HealthEntry] = []
    ) {
        self.id = id
        self.binStart = binStart
        self.binEnd = binEnd
        self.sum = sum
        self.count = count
        self.entries = entries
    }
    
    /// Calculate average
    var average: Double {
        count > 0 ? sum / Double(count) : 0
    }
    
    /// Center date for display
    var displayDate: Date {
        Date(timeIntervalSince1970: (binStart.timeIntervalSince1970 + binEnd.timeIntervalSince1970) / 2)
    }
}

// MARK: - ChartDataRange
/// Date range covered by the chart.
struct ChartDataRange: Equatable {
    let start: Date
    let end: Date
    
    var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
    
    func contains(_ date: Date) -> Bool {
        date >= start && date <= end
    }
    
    /// Extend range
    func extended(by interval: TimeInterval) -> ChartDataRange {
        ChartDataRange(
            start: start.addingTimeInterval(-interval),
            end: end.addingTimeInterval(interval)
        )
    }
}

// MARK: - VisibleWindow
/// Visible window information in the chart.
struct VisibleWindow: Equatable {
    let centerDate: Date
    let visibleRange: ChartDataRange
    let bufferRange: ChartDataRange  // Extra area for buffer
    
    init(centerDate: Date, visibleLength: TimeInterval, bufferMultiplier: Double = 2.0) {
        self.centerDate = centerDate
        
        let halfVisible = visibleLength / 2
        self.visibleRange = ChartDataRange(
            start: centerDate.addingTimeInterval(-halfVisible),
            end: centerDate.addingTimeInterval(halfVisible)
        )
        
        let halfBuffer = visibleLength * bufferMultiplier / 2
        self.bufferRange = ChartDataRange(
            start: centerDate.addingTimeInterval(-halfBuffer),
            end: centerDate.addingTimeInterval(halfBuffer)
        )
    }
}


