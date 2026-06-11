import Foundation
import CoreData
import Combine

struct DailyHealthMetric: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let activeEnergyBurned: Double?
    let stepCount: Double?
    let distanceWalkingRunning: Double?
    
    init(
        id: UUID = UUID(),
        date: Date,
        activeEnergyBurned: Double? = nil,
        stepCount: Double? = nil,
        distanceWalkingRunning: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.activeEnergyBurned = activeEnergyBurned
        self.stepCount = stepCount
        self.distanceWalkingRunning = distanceWalkingRunning
    }
    
    init(from entity: DailyHealthStat) {
        self.id = entity.id ?? UUID()
        self.date = entity.date ?? Date()
        self.activeEnergyBurned = entity.activeEnergyBurned != 0 ? entity.activeEnergyBurned : nil
        self.stepCount = entity.stepCount != 0 ? entity.stepCount : nil
        self.distanceWalkingRunning = entity.distanceWalkingRunning != 0 ? entity.distanceWalkingRunning : nil
    }
}

final class DailyHealthStore: NSObject, ObservableObject {
    static let shared = DailyHealthStore()
    
    private let persistence: Persistence
    private let context: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    private let writeQueue = DispatchQueue(label: "com.mneme.dailyhealthstore.write", qos: .userInitiated)
    private var hasDailyHealthStatEntity: Bool {
        context.persistentStoreCoordinator?.managedObjectModel.entitiesByName["DailyHealthStat"] != nil
    }
    
    init(persistence: Persistence = PersistenceController.shared) {
        self.persistence = persistence
        self.context = persistence.viewContext
        self.backgroundContext = persistence.newBackgroundContext()
        super.init()
        
        // Merge changes from background context to view context
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contextDidSave(_:)),
            name: .NSManagedObjectContextDidSave,
            object: backgroundContext
        )
    }
    
    @objc private func contextDidSave(_ notification: Notification) {
        context.perform {
            self.context.mergeChanges(fromContextDidSave: notification)
        }
    }
    
    func getMetric(for date: Date) -> DailyHealthMetric? {
        guard hasDailyHealthStatEntity else { return nil }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        
        let request: NSFetchRequest<DailyHealthStat> = DailyHealthStat.fetchRequest()
        request.predicate = NSPredicate(format: "date == %@", dayStart as CVarArg)
        request.fetchLimit = 1
        
        do {
            let results = try context.fetch(request)
            if let entity = results.first {
                return DailyHealthMetric(from: entity)
            }
        } catch {
            print("Error fetching daily health stat: \(error)")
        }
        
        return nil
    }
    
    func saveMetric(date: Date, activeEnergy: Double? = nil, stepCount: Double? = nil, distance: Double? = nil) async {
        guard hasDailyHealthStatEntity else { return }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        
        // Use serial queue to prevent race conditions
        await withCheckedContinuation { continuation in
            writeQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                self.backgroundContext.performAndWait {
                    let request: NSFetchRequest<DailyHealthStat> = DailyHealthStat.fetchRequest()
                    request.predicate = NSPredicate(format: "date == %@", dayStart as CVarArg)
                    request.fetchLimit = 1
                    
                    let stat: DailyHealthStat
                    
                    if let results = try? self.backgroundContext.fetch(request), let existing = results.first {
                        stat = existing
                        stat.modifiedAt = Date()
                    } else {
                        stat = DailyHealthStat(context: self.backgroundContext)
                        stat.id = UUID()
                        stat.createdAt = Date()
                        stat.modifiedAt = Date()
                        stat.date = dayStart
                    }
                    
                    if let activeEnergy = activeEnergy {
                        stat.activeEnergyBurned = activeEnergy
                    }
                    
                    if let stepCount = stepCount {
                        stat.stepCount = stepCount
                    }
                    
                    if let distance = distance {
                        stat.distanceWalkingRunning = distance
                    }
                    
                    if self.backgroundContext.hasChanges {
                        try? self.backgroundContext.save()
                    }
                }
                
                continuation.resume()
            }
        }
    }
}
