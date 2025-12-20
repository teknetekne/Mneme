import Foundation
import Combine

// MARK: - ChartWindowManager
/// Sonsuz yatay kaydirma icin kayan pencere (sliding window) yonetimi.
/// Kullanici sola (gecmise) kaydirdikca yeni tarih araliklari ekler.
@MainActor
final class ChartWindowManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published private(set) var loadedRange: ChartDataRange
    @Published private(set) var isLoading: Bool = false
    
    // MARK: - Configuration
    private let calendar: Calendar
    private let period: ChartPeriod
    private let pageSize: TimeInterval      // Her sayfa ne kadar veri yukler
    private let loadThreshold: Double       // Ne zaman yeni veri yuklenecek (0.0-1.0)
    
    // MARK: - Data Loading
    private var loadTask: Task<Void, Never>?
    var onLoadMore: ((ChartDataRange) async -> [HealthEntry])?
    
    // MARK: - Initialization
    init(
        initialDate: Date = Date(),
        period: ChartPeriod,
        calendar: Calendar = .current,
        loadThreshold: Double = 0.3
    ) {
        self.calendar = calendar
        self.period = period
        self.loadThreshold = loadThreshold
        
        // Periyoda gore sayfa boyutunu belirle
        self.pageSize = Self.pageSize(for: period)
        
        // Baslangic araligini olustur (simdi ve geri)
        let end = initialDate
        let start = end.addingTimeInterval(-pageSize * 2)
        self.loadedRange = ChartDataRange(start: start, end: end)
    }
    
    // MARK: - Page Size
    private static func pageSize(for period: ChartPeriod) -> TimeInterval {
        switch period {
        case .day:
            // 1 gun = 24 saat
            return 24 * 60 * 60
        case .week:
            // 2 hafta = 14 gun (kaydirma tamponu)
            return 14 * 24 * 60 * 60
        case .month:
            // ~2 ay = 60 gun
            return 60 * 24 * 60 * 60
        case .year:
            // ~2 yil tampon
            return 720 * 24 * 60 * 60
        }
    }
    
    // MARK: - Scroll Position Update
    /// Kaydirma konumu degistiginde cagrilir.
    /// Eger kullanici yuklu verinin baslangicina yaklasiyorsa, daha eski veri yukler.
    func onScrollPositionChanged(_ scrollDate: Date) {
        guard !isLoading else { return }
        
        // Yuklu araliga gore konumu hesapla
        let loadedDuration = loadedRange.duration
        let positionInRange = scrollDate.timeIntervalSince(loadedRange.start)
        let normalizedPosition = positionInRange / loadedDuration
        
        // Eger kullanici baslangica yakinsa (threshold icinde), daha eski veri yukle
        if normalizedPosition < loadThreshold {
            loadMoreHistory()
        }
    }
    
    // MARK: - Load More History
    /// Gecmise dogru daha fazla veri yukle.
    private func loadMoreHistory() {
        guard !isLoading else { return }
        
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            
            await MainActor.run {
                self.isLoading = true
            }
            
            // Yeni aralik: mevcut baslangictan bir sayfa geri
            let newStart = loadedRange.start.addingTimeInterval(-pageSize)
            let newRange = ChartDataRange(start: newStart, end: loadedRange.start)
            
            // Veri yukleme callback'i cagir
            if let loader = onLoadMore {
                _ = await loader(newRange)
            }
            
            await MainActor.run {
                // Yuklu araligi guncelle
                self.loadedRange = ChartDataRange(
                    start: newStart,
                    end: self.loadedRange.end
                )
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Reset
    /// Pencereyi sifirla ve yeniden baslat.
    func reset(to date: Date = Date()) {
        loadTask?.cancel()
        
        let end = date
        let start = end.addingTimeInterval(-pageSize * 2)
        loadedRange = ChartDataRange(start: start, end: end)
        isLoading = false
    }
    
    // MARK: - Period Change
    /// Periyod degistiginde araligi yeniden hesapla.
    func updatePeriod(_ newPeriod: ChartPeriod) -> ChartWindowManager {
        ChartWindowManager(
            initialDate: Date(),
            period: newPeriod,
            calendar: calendar,
            loadThreshold: loadThreshold
        )
    }
}

// MARK: - Axis Optimization
extension ChartWindowManager {
    
    /// Sadece gorunen alan icin eksen etiketlerini hesapla.
    /// CPU kullanimi optimizasyonu saglar.
    func visibleAxisDates(
        visibleRange: ChartDataRange,
        desiredCount: Int
    ) -> [Date] {
        let component: Calendar.Component
        switch period {
        case .day: component = .hour
        case .week, .month: component = .day
        case .year: component = .month
        }
        
        var dates: [Date] = []
        var currentDate = calendar.dateInterval(of: component, for: visibleRange.start)?.start ?? visibleRange.start
        
        // Gorunen aralik icindeki tarihleri topla
        while currentDate <= visibleRange.end && dates.count < desiredCount * 2 {
            if currentDate >= visibleRange.start {
                dates.append(currentDate)
            }
            
            guard let next = calendar.date(byAdding: component, value: 1, to: currentDate) else {
                break
            }
            currentDate = next
        }
        
        // Istenen sayiya gore filtrele
        if dates.count > desiredCount {
            let step = dates.count / desiredCount
            dates = stride(from: 0, to: dates.count, by: max(1, step)).map { dates[$0] }
        }
        
        return dates
    }
}


