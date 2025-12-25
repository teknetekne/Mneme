import Foundation

/// Represents a single data point for charts
struct ChartDataPoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let value: Double
    let label: String?
    
    init(date: Date, value: Double, label: String? = nil) {
        self.date = date
        self.value = value
        self.label = label
    }
    
    var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
    
    var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
    
    var dayNumber: Int {
        Calendar.current.component(.day, from: date)
    }
}

/// Chart type enum for styling
enum ChartType {
    case productivity
    case calories
    case balance
    
    var title: String {
        switch self {
        case .productivity: return "Productivity"
        case .calories: return "Calories"
        case .balance: return "Balance"
        }
    }
    
    var systemImage: String {
        switch self {
        case .productivity: return "briefcase.fill"
        case .calories: return "flame.fill"
        case .balance: return "dollarsign.circle.fill"
        }
    }
    
    var unit: String {
        switch self {
        case .productivity: return "hours"
        case .calories: return "kcal"
        case .balance: return ""
        }
    }
}

