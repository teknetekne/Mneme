import Foundation
import Combine
import SwiftUI

// MARK: - HealthChartViewModel
/// Main ViewModel for Apple Health-style charts.
/// Handles data loading, aggregation, and visible window management.
@MainActor
final class HealthChartViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Selected period (D/W/M/Y)
    @Published var period: ChartPeriod = .week {
        didSet {
            if oldValue != period {
                onPeriodChanged()
            }
        }
    }
    
    /// Scroll position (chart's center date)
    @Published var scrollPosition: Date = Date()
    
    /// User selection (tapped bar)
    @Published var selection: Date?
    
    /// Aggregated and sliced data (visible area only)
    @Published private(set) var visibleData: [AggregatedEntry] = []
    
    /// All aggregated data (cache)
    @Published private(set) var allAggregatedData: [AggregatedEntry] = []
    
    /// Statistics
    @Published private(set) var statistics: ChartStatistics = ChartStatistics(
        average: 0, peak: 0, total: 0, count: 0
    )
    
    /// Loading state
    @Published private(set) var isLoading: Bool = false
    
    // MARK: - Configuration
    private let calendar: Calendar
    private var windowManager: ChartWindowManager
    private var rawEntries: [HealthEntry] = []
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Data Provider
    var dataProvider: ((ChartDataRange) async -> [HealthEntry])?
    
    // MARK: - Initialization
    init(
        period: ChartPeriod = .week,
        calendar: Calendar = .current
    ) {
        self.period = period
        self.calendar = calendar
        self.windowManager = ChartWindowManager(
            initialDate: Date(),
            period: period,
            calendar: calendar
        )
        
        setupBindings()
    }
    
    // MARK: - Setup
    private func setupBindings() {
        // Notify window manager when scroll position changes
        $scrollPosition
            .removeDuplicates()
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] date in
                guard let self else { return }
                self.windowManager.onScrollPositionChanged(date)
                self.updateVisibleData()
            }
            .store(in: &cancellables)
        
        // Monitor window manager loading state
        windowManager.$isLoading
            .assign(to: &$isLoading)
        
        // Load new data when window manager range changes
        windowManager.$loadedRange
            .removeDuplicates()
            .sink { [weak self] range in
                Task { [weak self] in
                    await self?.loadDataForRange(range)
                }
            }
            .store(in: &cancellables)
        
        // Data loading callback
        windowManager.onLoadMore = { [weak self] range in
            guard let self else { return [] }
            return await self.fetchData(for: range)
        }
    }
    
    // MARK: - Period Change
    private func onPeriodChanged() {
        // Update window manager for new period
        windowManager = windowManager.updatePeriod(period)
        
        // Reset callback
        windowManager.onLoadMore = { [weak self] range in
            guard let self else { return [] }
            return await self.fetchData(for: range)
        }
        
        // Re-aggregate existing data
        reAggregateData()
        
        // Re-establish bindings
        setupBindings()
    }
    
    // MARK: - Data Loading
    
    /// Load data for a specific range
    private func loadDataForRange(_ range: ChartDataRange) async {
        let newEntries = await fetchData(for: range)
        
        // Add to existing data (with duplicate check)
        let existingIds = Set(rawEntries.map(\.id))
        let uniqueNewEntries = newEntries.filter { !existingIds.contains($0.id) }
        
        rawEntries.append(contentsOf: uniqueNewEntries)
        rawEntries.sort { $0.date < $1.date }
        
        // Re-aggregate
        reAggregateData()
    }
    
    /// Fetch data from data provider
    private func fetchData(for range: ChartDataRange) async -> [HealthEntry] {
        guard let provider = dataProvider else { return [] }
        return await provider(range)
    }
    
    /// Re-aggregate raw data by period
    private func reAggregateData() {
        allAggregatedData = ChartAggregator.aggregate(
            entries: rawEntries,
            by: period,
            calendar: calendar
        )
        
        // Update statistics
        statistics = ChartAggregator.statistics(for: allAggregatedData)
        
        // Update visible data
        updateVisibleData()
    }
    
    // MARK: - Visible Data Slicing
    
    /// Filter data within visible area + buffer
    private func updateVisibleData() {
        let window = VisibleWindow(
            centerDate: scrollPosition,
            visibleLength: period.visibleLength,
            bufferMultiplier: 2.5  // 2.5x buffer for smooth scrolling
        )
        
        visibleData = ChartAggregator.slice(
            entries: allAggregatedData,
            for: window
        )
    }
    
    // MARK: - Selection
    
    /// Return selected data point
    var selectedEntry: AggregatedEntry? {
        guard let selection else { return nil }
        
        return visibleData.min(by: {
            abs($0.displayDate.timeIntervalSince(selection)) <
            abs($1.displayDate.timeIntervalSince(selection))
        })
    }
    
    // MARK: - Chart Configuration
    
    var configuration: ChartConfiguration {
        ChartConfiguration(period: period)
    }
    
    /// Y-axis domain (headroom + nice rounding)
    var yDomain: ClosedRange<Double> {
        guard !visibleData.isEmpty else { return defaultDomain }
        
        let maxValue = visibleData.map(\.sum).max() ?? 0
        let minValue = visibleData.map(\.sum).min() ?? 0
        
        // 20% headroom at top, start from 0 at bottom
        let paddedMax = maxValue * 1.2
        let roundedMax = niceCeil(paddedMax)
        
        let lower = max(minValue * 0.9, 0)
        let domain = lower...roundedMax
        return clampDomain(domain)
    }
    
    // MARK: - Public Methods
    
    /// Load sample data (for test/demo)
    func loadSampleData() {
        let now = Date()
        var entries: [HealthEntry] = []
        
        // Generate random step data for last 90 days
        for dayOffset in 0..<90 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else {
                continue
            }
            
            // Data for entire day (0:00 - 23:00)
            for hour in 0..<24 {
                guard let hourDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) else {
                    continue
                }
                
                // Low activity at night, high activity during day
                let baseSteps: Double
                if hour >= 0 && hour < 6 {
                    // Night - very low (sleep)
                    baseSteps = Double.random(in: 0...30)
                } else if hour >= 7 && hour <= 9 {
                    // Morning walk - high
                    baseSteps = Double.random(in: 800...2000)
                } else if hour >= 17 && hour <= 19 {
                    // Evening walk - high
                    baseSteps = Double.random(in: 600...1500)
                } else if hour >= 12 && hour <= 13 {
                    // Lunch break - medium
                    baseSteps = Double.random(in: 300...800)
                } else if hour >= 22 {
                    // Late evening - low
                    baseSteps = Double.random(in: 20...100)
                } else {
                    // Normal activity
                    baseSteps = Double.random(in: 50...400)
                }
                
                entries.append(HealthEntry(date: hourDate, value: baseSteps))
            }
        }
        
        rawEntries = entries
        
        // Set scroll position to middle of day in day mode
        if period == .day {
            if let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now) {
                scrollPosition = noon
            }
        }
        
        reAggregateData()
    }
    
    /// Scroll to a specific date
    func scrollTo(date: Date, animated: Bool = true) {
        if animated {
            withAnimation(.easeInOut(duration: 0.3)) {
                scrollPosition = date
            }
        } else {
            scrollPosition = date
        }
    }
    
    /// Clear selection
    func clearSelection() {
        selection = nil
    }
    
    /// Return to today
    func scrollToToday() {
        scrollTo(date: Date())
    }
}

// MARK: - Nice Rounding
private func niceCeil(_ value: Double) -> Double {
    guard value > 0 else { return 0 }
    
    // Round up using 1-2-5 series
    let exponent = floor(log10(value))
    let base = pow(10.0, exponent)
    let mantissa = value / base
    
    let niceMantissa: Double
    if mantissa <= 1 {
        niceMantissa = 1
    } else if mantissa <= 2 {
        niceMantissa = 2
    } else if mantissa <= 5 {
        niceMantissa = 5
    } else {
        niceMantissa = 10
    }
    
    return niceMantissa * base
}

// MARK: - Y Domain Helpers
private extension HealthChartViewModel {
    var defaultDomain: ClosedRange<Double> {
        switch period {
        case .day:
            return 0...3_000
        case .week, .month:
            return 0...30_000
        case .year:
            return 0...40_000
        }
    }
    
    func clampDomain(_ domain: ClosedRange<Double>) -> ClosedRange<Double> {
        switch period {
        case .day:
            return 0...max(domain.upperBound, 3_000)
        case .week, .month:
            return 0...max(domain.upperBound, 30_000)
        case .year:
            return 0...max(domain.upperBound, 40_000)
        }
    }
}

// MARK: - Mock Data Provider
extension HealthChartViewModel {
    
    /// Mock data provider for testing
    static func mockDataProvider() -> (ChartDataRange) async -> [HealthEntry] {
        return { range in
            var entries: [HealthEntry] = []
            let calendar = Calendar.current
            
            var currentDate = range.start
            while currentDate <= range.end {
                // Data for each hour
                for hour in 6..<22 {
                    guard let hourDate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: currentDate) else {
                        continue
                    }
                    
                    if hourDate >= range.start && hourDate <= range.end {
                        let steps = Double.random(in: 100...1500)
                        entries.append(HealthEntry(date: hourDate, value: steps))
                    }
                }
                
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: currentDate) else {
                    break
                }
                currentDate = nextDay
            }
            
            return entries
        }
    }
}

