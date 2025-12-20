import Foundation
import Combine
import CoreData

enum VariableType: String, Codable, CaseIterable {
    case expense = "expense"
    case income = "income"
    case meal = "meal"
    
    var displayName: String {
        switch self {
        case .expense: return "Expense"
        case .income: return "Income"
        case .meal: return "Meal (kcal)"
        }
    }
    
    var intent: String {
        return rawValue
    }
}

struct VariableData: Codable {
    var calories: Double?
    var grams: Double?
    var amount: Double?
}

struct VariableStruct: Identifiable {
    let id: UUID
    var name: String
    var value: String // Raw stored value (String or JSON)
    var type: VariableType
    var currency: String?
    
    // Computed properties for new fields
    var calories: Double?
    var grams: Double?
    var amount: Double?
    
    init(id: UUID = UUID(), name: String, value: String, type: VariableType, currency: String? = nil) {
        self.id = id
        self.name = name
        self.value = value
        self.type = type
        self.currency = currency
        
        parseValue()
    }
    
    // Helper to avoid naming conflict with Core Data entity
    static func from(entity: VariableEntity) -> VariableStruct {
        return VariableStruct(
            id: entity.id ?? UUID(),
            name: entity.name ?? "",
            value: entity.value ?? "",
            type: VariableType(rawValue: entity.type ?? "") ?? .expense,
            currency: entity.currency
        )
    }
    
    private mutating func parseValue() {
        if type == .meal {
            // Try parsing JSON
            if let data = value.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(VariableData.self, from: data) {
                self.calories = decoded.calories
                self.grams = decoded.grams
            } else {
                // Fallback for legacy or simple calorie values
                self.calories = Double(value)
            }
        } else {
            // Expense/Income
            self.amount = Double(value)
        }
    }
    
    static func createValueString(calories: Double?, grams: Double?) -> String {
        let data = VariableData(calories: calories, grams: grams, amount: nil)
        if let encoded = try? JSONEncoder().encode(data),
           let string = String(data: encoded, encoding: .utf8) {
            return string
        }
        return ""
    }
}

final class VariableStore: NSObject, ObservableObject {
    static let shared = VariableStore()
    
    @Published private(set) var variables: [VariableStruct] = []
    
    private var fetchedResultsController: NSFetchedResultsController<VariableEntity>?
    private let persistence: Persistence
    private let context: NSManagedObjectContext
    
    init(persistence: Persistence = PersistenceController.shared) {
        self.persistence = persistence
        self.context = persistence.viewContext
        super.init()
        setupFetchedResultsController()
        
        Task {
            if DataMigrationService.shared.needsMigration {
                try? await DataMigrationService.shared.performMigration()
            }
            await MainActor.run { self.refreshVariables() }
        }
    }
    
    private func setupFetchedResultsController() {
        let fetchRequest: NSFetchRequest<VariableEntity> = VariableEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \VariableEntity.name, ascending: true)]
        
        fetchedResultsController = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        
        fetchedResultsController?.delegate = self
        
        do {
            try fetchedResultsController?.performFetch()
            refreshVariables()
        } catch {
        }
    }
    
    @MainActor
    private func refreshVariables() {
        guard let fetchedObjects = fetchedResultsController?.fetchedObjects else {
            variables = []
            return
        }
        variables = fetchedObjects.map { VariableStruct.from(entity: $0) }
    }
    
    @MainActor
    func addVariable(name: String, value: String, type: VariableType, currency: String? = nil) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedName.isEmpty, !trimmedValue.isEmpty else { return }
        
        Task {
            try? await persistence.performBackgroundTask { context in
                // Remove existing variable with same name
                let fetchRequest: NSFetchRequest<VariableEntity> = VariableEntity.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "name ==[c] %@", trimmedName)
                
                if let existing = try? context.fetch(fetchRequest).first {
                    context.delete(existing)
                }
                
                let variableEntity = VariableEntity(context: context)
                variableEntity.id = UUID()
                variableEntity.name = trimmedName
                variableEntity.value = trimmedValue
                variableEntity.type = type.rawValue
                variableEntity.currency = currency
                variableEntity.createdAt = Date()
                variableEntity.modifiedAt = Date()
                return ()
            }
        }
    }
    
    func deleteVariable(_ variable: VariableStruct) {
        Task {
            try? await persistence.performBackgroundTask { context in
                let fetchRequest: NSFetchRequest<VariableEntity> = VariableEntity.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", variable.id as CVarArg)
                
                if let entity = try? context.fetch(fetchRequest).first {
                    context.delete(entity)
                }
                return ()
            }
        }
    }
    
    func getVariable(name: String) -> VariableStruct? {
        return variables.first { $0.name.lowercased() == name.lowercased() }
    }
    
    func getVariables(for intent: String) -> [VariableStruct] {
        return variables.filter { $0.type.intent == intent }
    }
    
    nonisolated static func getVariablesSnapshot() -> [VariableStruct] {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                return VariableStore.shared.variables
            }
        } else {
            return DispatchQueue.main.sync {
                return VariableStore.shared.variables
            }
        }
    }
}

extension VariableStore: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        Task { @MainActor in
            refreshVariables()
        }
    }
}
