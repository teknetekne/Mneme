import Foundation

/// Central service for aggregating chart data from various stores
final class ChartDataProvider {
    static let shared = ChartDataProvider()
    
    private let workSessionStore = WorkSessionStore.shared
    private let notepadEntryStore = NotepadEntryStore.shared
    private let healthKitService = HealthKitService.shared
    private let currencySettingsStore = CurrencySettingsStore.shared
    
    private init() {}
    
    // MARK: - Productivity Data
    
    /// Get work hours aggregated by time period
    func getProductivityData(period: ChartTimePeriod = .day) -> [ChartDataPoint] {
        let rawData = getRawProductivityData(days: period.fetchDays)
        return aggregateData(rawData, by: period)
    }
    
    /// Get raw work hours per day for the last N days
    private func getRawProductivityData(days: Int) -> [ChartDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var dataPoints: [ChartDataPoint] = []
        
        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            
            if let workData = workSessionStore.getTotalWorkDuration(for: date) {
                let hours = Double(workData.minutes) / 60.0
                dataPoints.append(ChartDataPoint(
                    date: date,
                    value: hours,
                    label: workData.object
                ))
            } else {
                dataPoints.append(ChartDataPoint(date: date, value: 0))
            }
        }
        
        return dataPoints.sorted { $0.date < $1.date }
    }
    
    // MARK: - Calories Data
    
    /// Get net calories aggregated by time period
    func getCaloriesData(period: ChartTimePeriod = .day) async -> [ChartDataPoint] {
        let rawData = await getRawCaloriesData(days: period.fetchDays)
        return aggregateData(rawData, by: period)
    }
    
    /// Get raw net calories per day for the last N days
    private func getRawCaloriesData(days: Int) async -> [ChartDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var dataPoints: [ChartDataPoint] = []
        
        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            
            let dayEntries = notepadEntryStore.getEntries(for: date)
            var totalCalories: Double = 0.0
            
            // Add meal calories
            for entry in dayEntries {
                if let kcal = entry.mealKcal {
                    totalCalories += kcal
                }
            }
            
            // Subtract active energy burned from HealthKit
            if healthKitService.isAuthorized {
                if let activeEnergy = await healthKitService.getActiveEnergyBurned(for: date) {
                    totalCalories -= activeEnergy
                }
            }
            
            dataPoints.append(ChartDataPoint(date: date, value: totalCalories))
        }
        
        return dataPoints.sorted { $0.date < $1.date }
    }
    
    // MARK: - Balance Data
    
    /// Get net balance aggregated by time period
    func getBalanceData(period: ChartTimePeriod = .day) async -> [ChartDataPoint] {
        let rawData = await getRawBalanceData(days: period.fetchDays)
        return aggregateData(rawData, by: period)
    }
    
    /// Get raw net balance (income - expense) per day for the last N days
    private func getRawBalanceData(days: Int) async -> [ChartDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let currencyService = CurrencyService.shared
        let baseCurrency = currencySettingsStore.baseCurrency
        var dataPoints: [ChartDataPoint] = []
        
        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            
            let dayEntries = notepadEntryStore.getEntries(for: date)
            var dailyNetChange: Double = 0.0
            
            for entry in dayEntries {
                if (entry.intent == "income" || entry.intent == "expense"),
                   let amount = entry.amount,
                   let currency = entry.currency {
                    let amountDouble = Double(amount)
                    if let convertedAmount = await currencyService.convertAmount(abs(amountDouble), from: currency, to: baseCurrency) {
                        dailyNetChange += Double(entry.intent == "expense" ? -convertedAmount : convertedAmount)
                    } else {
                        dailyNetChange += Double(entry.intent == "expense" ? -amountDouble : amountDouble)
                    }
                }
            }
            
            dataPoints.append(ChartDataPoint(
                date: date,
                value: dailyNetChange,
                label: baseCurrency
            ))
        }
        
        return dataPoints.sorted { $0.date < $1.date }
    }
    
    // MARK: - Mood Data
    
    /// Get mood scores aggregated by time period (1-5 scale)
    func getMoodData(period: ChartTimePeriod = .day) -> [ChartDataPoint] {
        let rawData = getRawMoodData(days: period.fetchDays)
        return aggregateMoodData(rawData, by: period)
    }
    
    private let moodEmojis: [String: Double] = [
        "😢": 1.0,
        "😕": 2.0,
        "😐": 3.0,
        "🙂": 4.0,
        "😊": 5.0
    ]
    
    /// Get raw mood scores per day
    private func getRawMoodData(days: Int) -> [ChartDataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var dataPoints: [ChartDataPoint] = []
        
        for dayOffset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            
            let dayEntries = notepadEntryStore.getEntries(for: date)
            var moodScore: Double? = nil
            var moodLabel: String? = nil
            
            for entry in dayEntries {
                if entry.intent == "journal" {
                    // Look for mood emoji at start of text
                    for (emoji, score) in moodEmojis {
                        if entry.originalText.hasPrefix(emoji) {
                            moodScore = score
                            moodLabel = emoji
                            break
                        }
                    }
                    if moodScore != nil { break }
                }
            }
            
            if let score = moodScore {
                dataPoints.append(ChartDataPoint(date: date, value: score, label: moodLabel))
            }
        }
        
        return dataPoints.sorted { $0.date < $1.date }
    }
    
    /// Aggregate mood data by averaging scores
    private func aggregateMoodData(_ data: [ChartDataPoint], by period: ChartTimePeriod) -> [ChartDataPoint] {
        guard !data.isEmpty else { return [] }
        
        if period == .day {
            return Array(data.suffix(period.dataPointCount))
        }
        
        let calendar = Calendar.current
        var grouped: [String: (date: Date, total: Double, count: Int)] = [:]
        
        for point in data {
            let key = groupingKey(for: point.date, period: period, calendar: calendar)
            if var existing = grouped[key] {
                existing.total += point.value
                existing.count += 1
                grouped[key] = existing
            } else {
                grouped[key] = (date: point.date, total: point.value, count: 1)
            }
        }
        
        // Convert to average mood scores
        var result = grouped.map { (key, value) -> ChartDataPoint in
            let periodStartDate = startOfPeriod(for: value.date, period: period, calendar: calendar)
            let averageMood = value.total / Double(value.count)
            return ChartDataPoint(date: periodStartDate, value: averageMood)
        }
        
        result.sort { $0.date < $1.date }
        return Array(result.suffix(period.dataPointCount))
    }
    
    // MARK: - Data Aggregation
    
    /// Aggregate raw daily data by the specified time period
    private func aggregateData(_ data: [ChartDataPoint], by period: ChartTimePeriod) -> [ChartDataPoint] {
        guard !data.isEmpty else { return [] }
        
        if period == .day {
            // No aggregation needed for daily view
            return Array(data.suffix(period.dataPointCount))
        }
        
        let calendar = Calendar.current
        var grouped: [String: (date: Date, total: Double, count: Int)] = [:]
        
        for point in data {
            let key = groupingKey(for: point.date, period: period, calendar: calendar)
            if var existing = grouped[key] {
                existing.total += point.value
                existing.count += 1
                grouped[key] = existing
            } else {
                grouped[key] = (date: point.date, total: point.value, count: 1)
            }
        }
        
        // Convert to data points
        var result = grouped.map { (key, value) -> ChartDataPoint in
            // Use the first date of the period for the data point
            let periodStartDate = startOfPeriod(for: value.date, period: period, calendar: calendar)
            return ChartDataPoint(date: periodStartDate, value: value.total)
        }
        
        // Sort by date and limit to data point count
        result.sort { $0.date < $1.date }
        return Array(result.suffix(period.dataPointCount))
    }
    
    private func groupingKey(for date: Date, period: ChartTimePeriod, calendar: Calendar) -> String {
        switch period {
        case .day:
            let components = calendar.dateComponents([.year, .month, .day], from: date)
            return "\(components.year!)-\(components.month!)-\(components.day!)"
        case .week:
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return "\(components.yearForWeekOfYear!)-W\(components.weekOfYear!)"
        case .month:
            let components = calendar.dateComponents([.year, .month], from: date)
            return "\(components.year!)-\(components.month!)"
        }
    }
    
    private func startOfPeriod(for date: Date, period: ChartTimePeriod, calendar: Calendar) -> Date {
        switch period {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return calendar.date(from: components) ?? date
        case .month:
            let components = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: components) ?? date
        }
    }
    
    // MARK: - Summary Statistics
    
    /// Calculate average value from data points
    func average(of dataPoints: [ChartDataPoint]) -> Double {
        guard !dataPoints.isEmpty else { return 0 }
        let total = dataPoints.reduce(0) { $0 + $1.value }
        return total / Double(dataPoints.count)
    }
    
    /// Calculate total value from data points
    func total(of dataPoints: [ChartDataPoint]) -> Double {
        dataPoints.reduce(0) { $0 + $1.value }
    }
    
    /// Get max value from data points
    func max(of dataPoints: [ChartDataPoint]) -> Double {
        dataPoints.map { $0.value }.max() ?? 0
    }
    
    /// Get min value from data points
    func min(of dataPoints: [ChartDataPoint]) -> Double {
        dataPoints.map { $0.value }.min() ?? 0
    }
}
