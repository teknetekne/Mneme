import Foundation
import SwiftUI

/// Configuration for the HealthChart based on the selected period.
/// Defines visual properties like dimensions and axis formatting.
struct ChartConfiguration {
    let period: ChartPeriod
    
    // MARK: - Dimensions
    
    /// Width of a single bar in the chart
    var barWidth: CGFloat {
        switch period {
        case .day: return 16
        case .week: return 24
        case .month: return 20
        case .year: return 16
        }
    }
    
    /// Spacing between bars
    var barSpacing: CGFloat {
        switch period {
        case .day: return 8
        case .week: return 12
        case .month: return 10
        case .year: return 8
        }
    }
    
    // MARK: - Axis Configuration
    
    /// Date format for the X-axis labels
    var axisLabelFormat: String {
        period.axisDateFormat
    }
    
    /// How many labels to show on the X-axis
    var targetLabelCount: Int {
        period.desiredMarkCount
    }
    
    // MARK: - Interaction
    
    /// Whether the chart supports selection/scrubbing
    var allowSelection: Bool {
        true
    }
}
