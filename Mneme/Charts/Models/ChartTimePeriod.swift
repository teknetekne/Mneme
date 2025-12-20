import Foundation

/// Time period options for chart filtering
enum ChartTimePeriod: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    
    var id: Self { self }
    
    var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }
    
    /// Number of data points to fetch (large for infinite scroll)
    var dataPointCount: Int {
        switch self {
        case .day: return 1000      // ~3 years of days
        case .week: return 200      // ~4 years of weeks
        case .month: return 60      // 5 years of months
        }
    }
    
    /// Number of days to fetch raw data
    var fetchDays: Int {
        switch self {
        case .day: return 1095     // 3 years
        case .week: return 1460    // 4 years
        case .month: return 1825   // 5 years
        }
    }
    
    /// Calendar component for grouping
    var calendarComponent: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }
    
    /// Format string for x-axis labels
    var dateFormat: String {
        switch self {
        case .day: return "EEE"       // Mon, Tue
        case .week: return "MMM d"    // Jan 15
        case .month: return "MMM"     // Jan
        }
    }
    
    /// Secondary format for detail labels
    var detailDateFormat: String {
        switch self {
        case .day: return "d MMM"     // 15 Jan
        case .week: return "MMM d-d"  // Jan 15-21
        case .month: return "MMMM yyyy"  // January 2024
        }
    }
}
