import Foundation

/// Canonical chart periods that mirror Health-style timelines.
enum ChartPeriod: String, CaseIterable, Identifiable {
    case day, week, month, year
    
    var id: Self { self }
    
    /// Visible domain length (seconds) for horizontal scrolling.
    var visibleLength: TimeInterval {
        switch self {
        case .day:
            return 24 * 60 * 60 // 24 saat
        case .week:
            return 7 * 24 * 60 * 60 // tam hafta
        case .month:
            return 35 * 24 * 60 * 60 // tum ay (~5 hafta)
        case .year:
            return 365 * 24 * 60 * 60 // tum yil
        }
    }
    
    /// Desired axis tick count for the X axis.
    var desiredMarkCount: Int {
        switch self {
        case .day: return 6   // 00, 04, 08, 12, 16, 20
        case .week: return 4  // hafta basi/ortasi/sonu
        case .month: return 6 // ~5-6 gunde bir
        case .year: return 12 // her ay
        }
    }
    
    /// Component used for scroll snapping.
    var scrollSnapComponent: DateComponents {
        switch self {
        case .day: return DateComponents(hour: 1)
        case .week: return DateComponents(day: 1)
        case .month: return DateComponents(day: 1)
        case .year: return DateComponents(month: 1)
        }
    }
    
    /// X-axis unit used for Charts' `.value` encoding.
    var dateUnit: Calendar.Component {
        switch self {
        case .day: return .hour
        case .week, .month: return .day
        case .year: return .month
        }
    }
    
    /// X-axis label description.
    var xLabel: String {
        switch self {
        case .day: return "Hour"
        case .week, .month: return "Day"
        case .year: return "Month"
        }
    }
    
    /// Date format string for axis labels.
    var axisDateFormat: String {
        switch self {
        case .day: return "HH"
        case .week: return "EEE"
        case .month: return "d"
        case .year: return "MMM"
        }
    }
}

