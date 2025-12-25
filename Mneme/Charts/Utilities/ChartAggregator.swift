import Foundation

// MARK: - ChartAggregator
/// Veri kumeleme (aggregation) islemlerini yoneten utility.
/// DateBins API'si (iOS 16+) veya Dictionary(grouping:) kullanarak
/// verileri D/W/M/Y bazinda gruplar.
enum ChartAggregator {
    
    // MARK: - DateBins Aggregation (iOS 16+)
    /// DateBins kullanarak verileri belirli bir periyoda gore gruplar.
    /// DateBins, artik yillari ve degisen ay gunlerini dogru sekilde ele alir.
    static func aggregate(
        entries: [HealthEntry],
        by period: ChartPeriod,
        calendar: Calendar = .current
    ) -> [AggregatedEntry] {
        guard !entries.isEmpty else { return [] }
        
        // Tarih araligini belirle
        let sortedEntries = entries.sorted { $0.date < $1.date }
        guard let firstDate = sortedEntries.first?.date,
              let lastDate = sortedEntries.last?.date else {
            return []
        }
        
        // Periyoda gore bin boyutunu belirle
        let binSize = binComponent(for: period)
        
        // DateBins ile grupla
        let bins = createDateBins(
            from: firstDate,
            to: lastDate,
            component: binSize,
            calendar: calendar
        )
        
        // Her bin icin verileri topla
        return bins.compactMap { bin in
            let entriesInBin = sortedEntries.filter { entry in
                entry.date >= bin.start && entry.date < bin.end
            }
            
            guard !entriesInBin.isEmpty else { return nil }
            
            let sum = entriesInBin.reduce(0) { $0 + $1.value }
            
            return AggregatedEntry(
                binStart: bin.start,
                binEnd: bin.end,
                sum: sum,
                count: entriesInBin.count,
                entries: entriesInBin
            )
        }
    }
    
    // MARK: - Dictionary Grouping (Fallback)
    /// Dictionary(grouping:) kullanarak verileri gruplar.
    /// Daha eski iOS surumleri icin fallback olarak kullanilabilir.
    static func aggregateWithDictionary(
        entries: [HealthEntry],
        by period: ChartPeriod,
        calendar: Calendar = .current
    ) -> [AggregatedEntry] {
        guard !entries.isEmpty else { return [] }
        
        // Veriyi tarih anahtarina gore grupla
        let grouped = Dictionary(grouping: entries) { entry in
            binKey(for: entry.date, period: period, calendar: calendar)
        }
        
        // Gruplari AggregatedEntry'ye donustur
        return grouped.compactMap { (key, entries) -> AggregatedEntry? in
            guard !entries.isEmpty else { return nil }
            
            let (binStart, binEnd) = binRange(for: key, period: period, calendar: calendar)
            let sum = entries.reduce(0) { $0 + $1.value }
            
            return AggregatedEntry(
                binStart: binStart,
                binEnd: binEnd,
                sum: sum,
                count: entries.count,
                entries: entries
            )
        }
        .sorted { $0.binStart < $1.binStart }
    }
    
    // MARK: - Helpers
    
    /// Periyoda gore bin komponenti
    private static func binComponent(for period: ChartPeriod) -> Calendar.Component {
        switch period {
        case .day: return .hour
        case .week: return .day
        case .month: return .day
        case .year: return .month
        }
    }
    
    /// Tarih icin bin anahtari olustur
    private static func binKey(
        for date: Date,
        period: ChartPeriod,
        calendar: Calendar
    ) -> DateComponents {
        var components: Set<Calendar.Component>
        
        switch period {
        case .day:
            components = [.year, .month, .day, .hour]
        case .week, .month:
            components = [.year, .month, .day]
        case .year:
            components = [.year, .month]
        }
        
        return calendar.dateComponents(components, from: date)
    }
    
    /// DateComponents'tan bin araligini hesapla
    private static func binRange(
        for key: DateComponents,
        period: ChartPeriod,
        calendar: Calendar
    ) -> (start: Date, end: Date) {
        guard let startDate = calendar.date(from: key) else {
            return (Date(), Date())
        }
        
        let component: Calendar.Component
        switch period {
        case .day: component = .hour
        case .week, .month: component = .day
        case .year: component = .month
        }
        
        let endDate = calendar.date(byAdding: component, value: 1, to: startDate) ?? startDate
        
        return (startDate, endDate)
    }
    
    /// DateBins olustur (el ile uygulama)
    private static func createDateBins(
        from startDate: Date,
        to endDate: Date,
        component: Calendar.Component,
        calendar: Calendar
    ) -> [(start: Date, end: Date)] {
        var bins: [(start: Date, end: Date)] = []
        
        // Baslangic tarihini normalize et (komponente gore yuvarla)
        var currentStart = calendar.dateInterval(of: component, for: startDate)?.start ?? startDate
        
        while currentStart <= endDate {
            guard let interval = calendar.dateInterval(of: component, for: currentStart) else {
                break
            }
            
            bins.append((interval.start, interval.end))
            
            // Sonraki bin'e gec
            guard let nextStart = calendar.date(byAdding: component, value: 1, to: currentStart) else {
                break
            }
            currentStart = nextStart
        }
        
        return bins
    }
}

// MARK: - Visible Data Slicing
extension ChartAggregator {
    
    /// Sadece gorunen alan + buffer icindeki verileri dondur.
    /// Performans optimizasyonu icin kritik.
    static func slice(
        entries: [AggregatedEntry],
        for window: VisibleWindow
    ) -> [AggregatedEntry] {
        // Binary search ile baslangic ve bitis indekslerini bul
        let startIndex = partitioningIndex(of: entries) { entry in
            entry.binEnd > window.bufferRange.start
        }
        
        let endIndex = partitioningIndex(of: entries) { entry in
            entry.binStart >= window.bufferRange.end
        }
        
        guard startIndex < endIndex else { return [] }
        
        return Array(entries[startIndex..<endIndex])
    }
    
    /// Binary search ile partition noktasini bul.
    /// Swift Algorithms'teki partitioningIndex benzeri.
    private static func partitioningIndex<T>(
        of array: [T],
        where predicate: (T) -> Bool
    ) -> Int {
        var low = 0
        var high = array.count
        
        while low < high {
            let mid = (low + high) / 2
            if predicate(array[mid]) {
                high = mid
            } else {
                low = mid + 1
            }
        }
        
        return low
    }
}

// MARK: - Statistics
extension ChartAggregator {
    
    /// Istatistikleri hesapla
    static func statistics(for entries: [AggregatedEntry]) -> ChartStatistics {
        guard !entries.isEmpty else {
            return ChartStatistics(average: 0, peak: 0, total: 0, count: 0)
        }
        
        let total = entries.reduce(0) { $0 + $1.sum }
        let peak = entries.map(\.sum).max() ?? 0
        let average = total / Double(entries.count)
        
        return ChartStatistics(
            average: average,
            peak: peak,
            total: total,
            count: entries.count
        )
    }
}

// MARK: - ChartStatistics
struct ChartStatistics: Equatable {
    let average: Double
    let peak: Double
    let total: Double
    let count: Int
}



