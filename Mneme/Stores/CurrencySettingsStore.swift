import Foundation
import CoreData
import Combine

final class CurrencySettingsStore: ObservableObject {
    static let shared = CurrencySettingsStore()
    
    @Published var baseCurrency: String = "USD"
    @Published var exchangeRatesLastUpdated: Date?
    
    private let persistence: Persistence
    private let context: NSManagedObjectContext
    private var settingsEntity: CurrencySettings?
    
    init(persistence: Persistence = PersistenceController.shared) {
        self.persistence = persistence
        self.context = persistence.viewContext
        loadSettings()
        
        Task {
            if DataMigrationService.shared.needsMigration {
                try? await DataMigrationService.shared.performMigration()
            }
            await MainActor.run { self.loadSettings() }
        }
    }
    
    @MainActor
    private func loadSettings() {
        let fetchRequest: NSFetchRequest<CurrencySettings> = CurrencySettings.fetchRequest()
        fetchRequest.fetchLimit = 1
        
        if let settings = try? context.fetch(fetchRequest).first {
            settingsEntity = settings
            baseCurrency = settings.baseCurrency ?? "USD"
            exchangeRatesLastUpdated = settings.lastUpdated
        } else {
            // Create default settings
            let settings = CurrencySettings(context: context)
            settings.id = UUID()
            settings.baseCurrency = "USD"
            settings.lastUpdated = Date()
            settings.modifiedAt = Date()
            settingsEntity = settings
            
            do {
                try context.save()
            } catch {
            }
        }
    }
    
    @MainActor
    func setBaseCurrency(_ currency: String) {
        baseCurrency = currency
        
        Task {
            // Perform Core Data changes on a background context without relying on a non-existent backgroundContext
            guard let coordinator = context.persistentStoreCoordinator else { return }
            let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            backgroundContext.persistentStoreCoordinator = coordinator

            await backgroundContext.perform {
                let fetchRequest: NSFetchRequest<CurrencySettings> = CurrencySettings.fetchRequest()
                fetchRequest.fetchLimit = 1

                let settings: CurrencySettings
                if let existing = (try? backgroundContext.fetch(fetchRequest))?.first {
                    settings = existing
                } else {
                    let newSettings = CurrencySettings(context: backgroundContext)
                    newSettings.id = UUID()
                    settings = newSettings
                }

                settings.baseCurrency = currency
                settings.lastUpdated = Date()
                settings.modifiedAt = Date()

                do {
                    try backgroundContext.save()
                } catch {
                }
            }
        }
    }
    
    // MARK: - Exchange Rates Management
    
    @MainActor
    func refreshExchangeRates() async {
        // Trigger CurrencyService to fetch and save rates
        _ = await CurrencyService.shared.getExchangeRate(from: "USD", to: "EUR")
        
        // Reload settings to get updated timestamp
        loadSettings()
    }
    
    @MainActor
    func getExchangeRates() -> [String: Double]? {
        guard let settings = settingsEntity,
              let jsonString = settings.exchangeRatesJSON,
              let jsonData = jsonString.data(using: .utf8),
              let rates = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Double] else {
            return nil
        }
        return rates
    }
    
    func needsExchangeRatesUpdate() -> Bool {
        guard let lastUpdated = exchangeRatesLastUpdated else {
            return true
        }
        // Update if older than 24 hours
        return Date().timeIntervalSince(lastUpdated) > 24 * 3600
    }
}

