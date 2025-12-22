import Foundation
import CoreData

final class CurrencyService {
    static let shared = CurrencyService()
    
    // Hard-coded API URL for freecurrencyapi.com
    private let currencyAPIURL = "https://api.freecurrencyapi.com/v1/latest"
    
    // Use ProcessInfo environment (same as USDA_API_KEY) - can be set in Xcode scheme or .env via EnvironmentConfig
    private var currencyAPIKey: String? {
        return ProcessInfo.processInfo.environment["CURRENCY_API_KEY"]
    }
    
    private var ratesCache: [String: [String: Double]] = [:]
    private var cacheTimestamps: [String: Date] = [:]
    private let cacheValidityHours: TimeInterval = 6
    
    private let persistence: Persistence
    
    private init() {
        self.persistence = PersistenceController.shared
    }
    
    func getExchangeRate(from: String, to: String) async -> Double? {
        let fromUpper = from.uppercased()
        let toUpper = to.uppercased()
        
        // Same currency
        if fromUpper == toUpper {
            return 1.0
        }
        
        // Load USD-based rates (from API or Core Data)
        var usdRates: [String: Double]?
        
        // 1. Check in-memory cache first
        if let cached = ratesCache["usd"],
           let cacheDate = cacheTimestamps["usd"],
           Date().timeIntervalSince(cacheDate) < cacheValidityHours * 3600 {
            usdRates = cached
        }
        
        // 2. Try to load from Core Data
        if usdRates == nil {
            if let rates = await loadRatesFromStorage() {
                usdRates = rates
                // Cache it for this session
                var normalizedRates: [String: Double] = [:]
                for (key, value) in rates {
                    normalizedRates[key.uppercased()] = value
                }
                ratesCache["usd"] = normalizedRates
                cacheTimestamps["usd"] = Date()
            }
        }
        
        // 3. (Optional) If strictly no rates found anywhere, try fetch just in case
        if usdRates == nil {
            if let rates = await fetchRatesFromAPI() {
                 // Save to Core Data
                 await saveRatesToStorage(rates)
                 usdRates = rates
            }
        }
        
        // Calculate exchange rate from USD-based rates
        if let rates = usdRates {
            let fromRate = rates[fromUpper]
            let toRate = rates[toUpper]
            
            if let from = fromRate, let to = toRate {
                if fromUpper == "USD" { return to }
                if toUpper == "USD" { return 1.0 / from }
                return to / from
            }
        }
        
        return nil
    }
    
    func convertAmount(_ amount: Double, from: String, to: String) async -> Double? {
        guard let rate = await getExchangeRate(from: from, to: to) else {
            return nil
        }
        return amount * rate
    }
    
    // MARK: - Public Methods
    
    /// Trigger a refresh of exchange rates from the API
    /// This should be called on app launch
    func refreshRates() async {
        // Check if we have valid rates in storage first
        if let storedRates = await loadRatesFromStorage() {
             // We have valid (not expired) rates, so just update in-memory cache
             // and skip API call
             var normalizedRates: [String: Double] = [:]
             for (key, value) in storedRates {
                 normalizedRates[key.uppercased()] = value
             }
             ratesCache["usd"] = normalizedRates
             cacheTimestamps["usd"] = Date()
             return
        }
        
        // No valid rates found, fetch from API
        if let rates = await fetchRatesFromAPI() {
            await saveRatesToStorage(rates)
            
            // Update cache
            var normalizedRates: [String: Double] = [:]
            for (key, value) in rates {
                normalizedRates[key.uppercased()] = value
            }
            ratesCache["usd"] = normalizedRates
            cacheTimestamps["usd"] = Date()
        }
    }
    
    // MARK: - New API Methods
    
    private func fetchRatesFromAPI() async -> [String: Double]? {
        guard let url = URL(string: currencyAPIURL) else {
            return nil
        }
        
        guard let apiKey = currencyAPIKey, !apiKey.isEmpty else {
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return nil
            }
            
            let statusCode = httpResponse.statusCode
            
            if statusCode == 429 {
                return nil
            }
            
            guard statusCode == 200 else {
                return nil
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            
            guard let dataDict = json["data"] as? [String: Double] else {
                return nil
            }
            
            return dataDict
            
        } catch {
            return nil
        }
    }
    
    // MARK: - Core Data Storage Methods
    
    private func saveRatesToStorage(_ rates: [String: Double]) async {
        await MainActor.run {
            let context = persistence.viewContext
            
            let fetchRequest: NSFetchRequest<CurrencySettings> = CurrencySettings.fetchRequest()
            fetchRequest.fetchLimit = 1
            
            let settings: CurrencySettings
            if let existing = try? context.fetch(fetchRequest).first {
                settings = existing
            } else {
                settings = CurrencySettings(context: context)
                settings.id = UUID()
                settings.baseCurrency = "USD"
            }
            
            // Convert rates to JSON
            if let jsonData = try? JSONSerialization.data(withJSONObject: rates, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                settings.exchangeRatesJSON = jsonString
                settings.lastUpdated = Date()
                settings.modifiedAt = Date()
                
                do {
                    try context.save()
                } catch {
                }
            }
        }
    }
    
    private func loadRatesFromStorage() async -> [String: Double]? {
        await MainActor.run {
            let context = persistence.viewContext
            
            let fetchRequest: NSFetchRequest<CurrencySettings> = CurrencySettings.fetchRequest()
            fetchRequest.fetchLimit = 1
            
            guard let settings = try? context.fetch(fetchRequest).first,
                  let jsonString = settings.exchangeRatesJSON,
                  let jsonData = jsonString.data(using: .utf8),
                  let rates = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Double] else {
                return nil
            }
            
            // Check if data is still fresh (within cache validity period)
            if let lastUpdated = settings.lastUpdated,
               Date().timeIntervalSince(lastUpdated) < cacheValidityHours * 3600 {
                return rates
            }
            
            return nil
        }
    }
}

