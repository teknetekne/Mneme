import Foundation
import Combine
import CoreData

enum WorkStartResult {
    case success
    case needsConfirmation(existingSession: WorkSessionStruct)
}

struct WorkSessionStruct: Identifiable, Equatable {
    var id = UUID()
    let date: Date
    let startTime: String // HH:MM format
    let endTime: String? // HH:MM format, nil if not ended yet
    let object: String? // Work object/description
    
    enum CodingKeys: String, CodingKey {
        case id, date, startTime, endTime, object
    }
    
    init(id: UUID = UUID(), date: Date, startTime: String, endTime: String?, object: String?) {
        self.id = id
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.object = object
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        startTime = try container.decode(String.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(String.self, forKey: .endTime)
        object = try container.decodeIfPresent(String.self, forKey: .object)
    }
    
    var durationMinutes: Int? {
        guard let endTime = endTime else { return nil }
        let startComponents = startTime.split(separator: ":")
        let endComponents = endTime.split(separator: ":")
        guard startComponents.count == 2, endComponents.count == 2,
              let startHour = Int(startComponents[0]),
              let startMinute = Int(startComponents[1]),
              let endHour = Int(endComponents[0]),
              let endMinute = Int(endComponents[1]) else {
            return nil
        }
        let startTotal = startHour * 60 + startMinute
        let endTotal = endHour * 60 + endMinute
        
        // Handle sessions that cross midnight (e.g., 23:00 to 01:00 = 2 hours)
        var duration = endTotal - startTotal
        if duration < 0 {
            duration += 24 * 60 // Add 24 hours if negative (crossed midnight)
        }
        
        return duration > 0 ? duration : nil
    }
    
    init(from entity: WorkSession) {
        self.id = entity.id ?? UUID()
        self.date = entity.date ?? Date()
        self.startTime = entity.startTime ?? ""
        self.endTime = entity.endTime
        self.object = entity.object
    }
}

final class WorkSessionStore: NSObject, ObservableObject {
    static let shared = WorkSessionStore()
    
    @Published private(set) var sessions: [WorkSessionStruct] = []
    
    private var fetchedResultsController: NSFetchedResultsController<WorkSession>?
    private let persistence: Persistence
    private let context: NSManagedObjectContext
    private let shouldRunMigration: Bool
    
    override init() {
        self.persistence = PersistenceController.shared
        self.context = persistence.viewContext
        self.shouldRunMigration = true
        super.init()
        configureStore()
    }
    
    init(persistence: Persistence, runMigration: Bool = false) {
        self.persistence = persistence
        self.context = persistence.viewContext
        self.shouldRunMigration = runMigration
        super.init()
        configureStore()
    }
    
    private func configureStore() {
        setupFetchedResultsController()
        Task {
            if shouldRunMigration,
               DataMigrationService.shared.needsMigration {
                try? await DataMigrationService.shared.performMigration()
            }
            await MainActor.run {
                refreshSessions()
            }
        }
    }
    
    private func setupFetchedResultsController() {
        let fetchRequest: NSFetchRequest<WorkSession> = WorkSession.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \WorkSession.date, ascending: false)]
        
        fetchedResultsController = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        
        fetchedResultsController?.delegate = self
        
        do {
            try fetchedResultsController?.performFetch()
            refreshSessions()
        } catch {
        }
    }
    
    @MainActor
    private func refreshSessions() {
        guard let fetchedObjects = fetchedResultsController?.fetchedObjects else {
            sessions = []
            return
        }
        sessions = fetchedObjects.map { WorkSessionStruct(from: $0) }
    }
    
    func recordWorkStart(date: Date, time: String, object: String?, forceReplace: Bool = false) -> WorkStartResult {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        
        // Find all incomplete sessions (from any day)
        let incompleteSessions = sessions.filter { $0.endTime == nil }
        
        // If there are active sessions and we're not forcing replacement, return confirmation needed
        if !incompleteSessions.isEmpty && !forceReplace {
            // Return the most recent active session
            let mostRecent = incompleteSessions.sorted { $0.date > $1.date }.first!
            return .needsConfirmation(existingSession: mostRecent)
        }
        
        guard let coordinator = self.context.persistentStoreCoordinator else { return .success }
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        
        return context.performAndWait {
            // Clean up all incomplete sessions before starting a new one
            if !incompleteSessions.isEmpty {
                let fetchRequest: NSFetchRequest<WorkSession> = WorkSession.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "endTime == nil")
                
                if let incompleteEntities = try? context.fetch(fetchRequest) {
                    for entity in incompleteEntities {
                        context.delete(entity)
                    }
                }
            }
            
            // If object is specified, check if there's already an incomplete session with same object for this day
            if let object = object, !object.isEmpty {
                let normalizedObject = object.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let fetchRequest: NSFetchRequest<WorkSession> = WorkSession.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "date >= %@ AND date < %@ AND endTime == nil AND object ==[c] %@", dayStart as NSDate, calendar.date(byAdding: .day, value: 1, to: dayStart)! as NSDate, normalizedObject)
                
                if let existingEntity = try? context.fetch(fetchRequest).first {
                    existingEntity.startTime = time
                    existingEntity.modifiedAt = Date()
                    try? context.save()
                    return .success
                }
            }
            
            // Create new session
            let sessionEntity = WorkSession(context: context)
            sessionEntity.id = UUID()
            sessionEntity.date = date
            sessionEntity.startTime = time
            sessionEntity.endTime = nil
            sessionEntity.object = object
            sessionEntity.createdAt = date
            sessionEntity.modifiedAt = Date()
            sessionEntity.deviceId = getOrCreateDeviceId()
            
            try? context.save()
            return .success
        }
    }
    
    func recordWorkEnd(date: Date, time: String, object: String? = nil) -> WorkSessionStruct? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        
        guard let coordinator = self.context.persistentStoreCoordinator else { return nil }
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        
        return context.performAndWait {
            let fetchRequest: NSFetchRequest<WorkSession> = WorkSession.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "date >= %@ AND date < %@ AND endTime == nil", dayStart as NSDate, dayEnd as NSDate)
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \WorkSession.date, ascending: false)]
            
            guard let incompleteEntities = try? context.fetch(fetchRequest), !incompleteEntities.isEmpty else {
                return nil
            }
            
            var matchingEntity: WorkSession?
            
            // If object is specified, match by object
            if let object = object, !object.isEmpty {
                let normalizedObject = object.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                matchingEntity = incompleteEntities.first { entity in
                    let sessionObject = entity.object?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return sessionObject == normalizedObject || sessionObject.contains(normalizedObject) || normalizedObject.contains(sessionObject)
                }
            } else if incompleteEntities.count == 1 {
                matchingEntity = incompleteEntities.first
            } else {
                matchingEntity = incompleteEntities.first
            }
            
            guard let entity = matchingEntity else {
                return nil
            }
            
            entity.endTime = time
            entity.modifiedAt = Date()
            
            if let startTime = entity.startTime {
                let startComponents = startTime.split(separator: ":")
                let endComponents = time.split(separator: ":")
                if startComponents.count == 2, endComponents.count == 2,
                   let startHour = Int(startComponents[0]),
                   let startMinute = Int(startComponents[1]),
                   let endHour = Int(endComponents[0]),
                   let endMinute = Int(endComponents[1]) {
                    let startTotal = startHour * 60 + startMinute
                    let endTotal = endHour * 60 + endMinute
                    var duration = endTotal - startTotal
                    if duration < 0 {
                        duration += 24 * 60
                    }
                    entity.durationMinutes = Int32(duration > 0 ? duration : 0)
                }
            }
            
            try? context.save()
            return WorkSessionStruct(from: entity)
        }
    }
    
    func getWorkDuration(for date: Date) -> (minutes: Int, object: String?)? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        
        // Find completed session for this day
        guard let session = sessions.first(where: { session in
            let sessionDay = calendar.startOfDay(for: session.date)
            return sessionDay == dayStart && session.endTime != nil
        }),
        let duration = session.durationMinutes, duration > 0 else {
            return nil
        }
        
        return (duration, session.object)
    }
    
    func getTotalWorkDuration(for date: Date) -> (minutes: Int, object: String?)? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        
        // Find all completed sessions for this day using isDate for reliable comparison
        let completedSessions = sessions.filter { session in
            calendar.isDate(session.date, inSameDayAs: dayStart) && session.endTime != nil
        }
        
        guard !completedSessions.isEmpty else {
            return nil
        }
        
        // Calculate total duration
        var totalMinutes = 0
        var objectCounts: [String: Int] = [:]
        
        for session in completedSessions {
            if let duration = session.durationMinutes, duration > 0 {
                totalMinutes += duration
                
                if let object = session.object, !object.isEmpty {
                    objectCounts[object, default: 0] += 1
                }
            }
        }
        
        guard totalMinutes > 0 else {
            return nil
        }
        
        // Find the most common object
        let mostCommonObject = objectCounts.max(by: { $0.value < $1.value })?.key
        
        return (totalMinutes, mostCommonObject)
    }
    
    func getActiveWorkSession() -> WorkSessionStruct? {
        // Find the most recent active session (endTime == nil)
        return sessions.first(where: { $0.endTime == nil })
    }
    
    private func getOrCreateDeviceId() -> UUID {
        let key = "mneme_device_id"
        if let uuidString = UserDefaults.standard.string(forKey: key),
           let uuid = UUID(uuidString: uuidString) {
            return uuid
        }
        let uuid = UUID()
        UserDefaults.standard.set(uuid.uuidString, forKey: key)
        return uuid
    }
}

extension WorkSessionStore: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        Task { @MainActor in
            refreshSessions()
        }
    }
}
