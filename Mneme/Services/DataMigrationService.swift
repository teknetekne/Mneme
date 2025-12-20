import Foundation
import CoreData

enum MigrationStatus {
    case notStarted
    case inProgress
    case completed
    case failed(Error)
}

final class DataMigrationService {
    static let shared = DataMigrationService()
    
    private let migrationVersionKey = "mneme_coredata_migration_version"
    private let currentMigrationVersion = 1
    
    private init() {}
    
    var migrationVersion: Int {
        UserDefaults.standard.integer(forKey: migrationVersionKey)
    }
    
    var needsMigration: Bool {
        migrationVersion < currentMigrationVersion
    }
    
    var migrationStatus: MigrationStatus {
        if !needsMigration {
            return .completed
        }
        if UserDefaults.standard.bool(forKey: "mneme_migration_in_progress") {
            return .inProgress
        }
        if let errorData = UserDefaults.standard.data(forKey: "mneme_migration_error"),
           let error = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSError.self, from: errorData) {
            return .failed(error)
        }
        return .notStarted
    }
    
    func performMigration() async throws {
        guard needsMigration else { return }
        
        UserDefaults.standard.set(true, forKey: "mneme_migration_in_progress")
        UserDefaults.standard.removeObject(forKey: "mneme_migration_error")
        
        do {
            let persistence: Persistence = PersistenceController.shared
            try await persistence.performBackgroundTask { context in
                try self.migrateNotepadEntries(context: context)
                try self.migrateWorkSessions(context: context)
                try self.migrateVariables(context: context)
                try self.migrateReminderEventTags(context: context)
                try self.migrateCurrencySettings(context: context)
                try self.migrateUserSettings(context: context)
                return ()
            }
            
            UserDefaults.standard.set(currentMigrationVersion, forKey: migrationVersionKey)
            UserDefaults.standard.set(false, forKey: "mneme_migration_in_progress")
        } catch {
            let errorData = try? NSKeyedArchiver.archivedData(withRootObject: error as NSError, requiringSecureCoding: false)
            UserDefaults.standard.set(errorData, forKey: "mneme_migration_error")
            UserDefaults.standard.set(false, forKey: "mneme_migration_in_progress")
            throw error
        }
    }
    
    private func migrateNotepadEntries(context: NSManagedObjectContext) throws {
        let fileName = "notepad_entries.json"
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(fileName)
        
        // Legacy struct for decoding JSON
        struct LegacyParsedNotepadEntry: Codable {
            let id: UUID
            let date: Date
            let originalText: String
            let intent: String?
            let object: String?
            let reminderTime: String?
            let reminderDay: String?
            let eventTime: String?
            let eventDay: String?
            let currency: String?
            let amount: Double?
            let duration: Double?
            let distance: Double?
            let mealQuantity: String?
            let mealKcal: Double?
        }
        
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([LegacyParsedNotepadEntry].self, from: data) else {
            return
        }
        
        let fetchRequest: NSFetchRequest<ParsedEntry> = ParsedEntry.fetchRequest()
        let existingCount = try context.count(for: fetchRequest)
        
        if existingCount > 0 {
            return
        }
        
        let deviceId = getOrCreateDeviceId()
        let now = Date()
        
        for entry in entries {
            let parsedEntry = ParsedEntry(context: context)
            parsedEntry.id = entry.id
            parsedEntry.originalText = entry.originalText
            parsedEntry.intent = entry.intent
            parsedEntry.object = entry.object
            parsedEntry.reminderTime = entry.reminderTime
            parsedEntry.reminderDay = entry.reminderDay
            parsedEntry.eventTime = entry.eventTime
            parsedEntry.eventDay = entry.eventDay
            parsedEntry.currency = entry.currency
            parsedEntry.amount = entry.amount ?? 0
            parsedEntry.duration = entry.duration ?? 0
            parsedEntry.distance = entry.distance ?? 0
            parsedEntry.mealQuantity = entry.mealQuantity
            parsedEntry.mealKcal = entry.mealKcal ?? 0
            parsedEntry.createdAt = entry.date
            parsedEntry.modifiedAt = now
            parsedEntry.deviceId = deviceId
        }
    }
    
    private func migrateWorkSessions(context: NSManagedObjectContext) throws {
        let storageKey = "mneme_work_sessions"
        
        // Define a temporary struct for decoding legacy data
        struct LegacyWorkSession: Codable {
            var id: UUID
            let date: Date
            let startTime: String
            let endTime: String?
            let object: String?
        }
        
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let sessions = try? JSONDecoder().decode([LegacyWorkSession].self, from: data) else {
            return
        }
        
        let fetchRequest: NSFetchRequest<WorkSession> = WorkSession.fetchRequest()
        let existingCount = try context.count(for: fetchRequest)
        
        if existingCount > 0 {
            return
        }
        
        let deviceId = getOrCreateDeviceId()
        let now = Date()
        
        for session in sessions {
            let workSession = WorkSession(context: context)
            workSession.id = session.id
            workSession.date = session.date
            workSession.startTime = session.startTime
            workSession.endTime = session.endTime
            workSession.object = session.object
            
            // Calculate duration if endTime exists
            if let endTime = session.endTime {
                let startComponents = session.startTime.split(separator: ":")
                let endComponents = endTime.split(separator: ":")
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
                    workSession.durationMinutes = Int32(duration > 0 ? duration : 0)
                }
            }
            
            workSession.createdAt = session.date
            workSession.modifiedAt = now
            workSession.deviceId = deviceId
        }
    }
    
    private func migrateVariables(context: NSManagedObjectContext) throws {
        let storageKey = "mneme_variables"
        
        // Legacy struct for decoding JSON
        struct LegacyVariable: Codable {
            let id: UUID
            var name: String
            var value: String
            var type: VariableType
            var currency: String?
        }
        
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let variables = try? JSONDecoder().decode([LegacyVariable].self, from: data) else {
            return
        }
        
        let fetchRequest: NSFetchRequest<VariableEntity> = VariableEntity.fetchRequest()
        let existingCount = try context.count(for: fetchRequest)
        
        if existingCount > 0 {
            return
        }
        
        let now = Date()
        
        for variable in variables {
            let variableEntity = VariableEntity(context: context)
            variableEntity.id = variable.id
            variableEntity.name = variable.name
            variableEntity.value = variable.value
            variableEntity.type = variable.type.rawValue
            variableEntity.currency = variable.currency
            variableEntity.createdAt = now
            variableEntity.modifiedAt = now
        }
    }
    
    private func migrateReminderEventTags(context: NSManagedObjectContext) throws {
        let storageKey = "mneme_reminder_event_tags"
        
        // Define a temporary struct for decoding legacy data
        struct LegacyReminderEventTag: Codable {
            let id: UUID
            let lineId: UUID?
            let eventIdentifier: String?
            let reminderIdentifier: String?
            let tag: String
            let colorName: String
        }
        
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let tags = try? JSONDecoder().decode([LegacyReminderEventTag].self, from: data) else {
            return
        }
        
        let fetchRequest: NSFetchRequest<ReminderEventTag> = ReminderEventTag.fetchRequest()
        let existingCount = try context.count(for: fetchRequest)
        
        if existingCount > 0 {
            return
        }
        
        let now = Date()
        
        for tag in tags {
            let tagEntity = ReminderEventTag(context: context)
            tagEntity.id = tag.id
            tagEntity.lineId = tag.lineId
            tagEntity.eventIdentifier = tag.eventIdentifier
            tagEntity.reminderIdentifier = tag.reminderIdentifier
            tagEntity.tag = tag.tag
            tagEntity.colorName = tag.colorName
            tagEntity.createdAt = now
            tagEntity.modifiedAt = now
        }
    }
    
    private func migrateCurrencySettings(context: NSManagedObjectContext) throws {
        let baseCurrencyKey = "baseCurrency"
        let baseCurrency = UserDefaults.standard.string(forKey: baseCurrencyKey) ?? "USD"
        
        let fetchRequest: NSFetchRequest<CurrencySettings> = CurrencySettings.fetchRequest()
        let existingCount = try context.count(for: fetchRequest)
        
        if existingCount > 0 {
            return
        }
        
        let settings = CurrencySettings(context: context)
        settings.id = UUID()
        settings.baseCurrency = baseCurrency
        settings.lastUpdated = Date()
        settings.modifiedAt = Date()
    }
    
    private func migrateUserSettings(context: NSManagedObjectContext) throws {
        let heightKey = "userHeight"
        let weightKey = "userWeight"
        let ageKey = "userAge"
        let biologicalSexKey = "userBiologicalSex"
        
        let fetchRequest: NSFetchRequest<UserProfileEntity> = UserProfileEntity.fetchRequest()
        let existingCount = try context.count(for: fetchRequest)
        
        if existingCount > 0 {
            return
        }
        
        let profile = UserProfileEntity(context: context)
        profile.id = UUID()
        
        if let height = UserDefaults.standard.object(forKey: heightKey) as? Double {
            profile.heightCm = height
        }
        
        if let weight = UserDefaults.standard.object(forKey: weightKey) as? Double {
            profile.weightKg = weight
        }
        
        if let age = UserDefaults.standard.object(forKey: ageKey) as? Int {
            profile.age = Int32(age)
        }
        
        if let sexRaw = UserDefaults.standard.string(forKey: biologicalSexKey) {
            profile.biologicalSex = sexRaw
        }
        
        profile.modifiedAt = Date()
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
    
    func resetMigration() {
        UserDefaults.standard.removeObject(forKey: migrationVersionKey)
        UserDefaults.standard.removeObject(forKey: "mneme_migration_in_progress")
        UserDefaults.standard.removeObject(forKey: "mneme_migration_error")
    }
}
