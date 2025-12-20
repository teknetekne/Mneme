import Foundation
import CoreData

struct LegacyStoreMigrator {
    struct DataDump {
        var parsedEntries: [LegacyParsedEntry]
        var workSessions: [LegacyWorkSession]
        var variables: [LegacyVariable]
        var reminderTags: [LegacyReminderTag]
        var calorieCache: [LegacyCalorieCache]
        var currencySettings: [LegacyCurrencySetting]
        var userProfiles: [LegacyUserProfile]
    }

    struct LegacyParsedEntry {
        let id: UUID
        let originalText: String
        let intent: String?
        let object: String?
        let reminderDay: String?
        let reminderTime: String?
        let eventDay: String?
        let eventTime: String?
        let currency: String?
        let amount: Double?
        let duration: Double?
        let distance: Double?
        let mealQuantity: String?
        let mealKcal: Double?
        let source: String?
        let createdAt: Date
        let deviceId: UUID
    }

    struct LegacyWorkSession {
        let id: UUID
        let date: Date?
        let startTime: String?
        let endTime: String?
        let object: String?
        let durationMinutes: Int?
        let createdAt: Date?
        let deviceId: UUID?
    }

    struct LegacyVariable {
        let id: UUID
        let name: String?
        let type: String?
        let value: String?
        let currency: String?
        let createdAt: Date?
    }

    struct LegacyReminderTag {
        let id: UUID
        let tag: String?
        let colorName: String?
        let lineId: UUID?
        let eventIdentifier: String?
        let reminderIdentifier: String?
    }

    struct LegacyCalorieCache {
        let id: UUID
        let foodName: String?
        let calories: Double?
        let quantityDescriptor: String?
        let isMenu: Bool
        let sourcesJSON: String?
        let updatedAt: Date?
    }

    struct LegacyCurrencySetting {
        let id: UUID
        let baseCurrency: String?
        let lastUpdated: Date?
    }

    struct LegacyUserProfile {
        let id: UUID
        let height: Double?
        let weight: Double?
        let age: Int?
        let biologicalSex: String?
        let lastHealthSync: Date?
    }

    static func prepareMigrationIfNeeded(storeURL: URL?, managedObjectModel: NSManagedObjectModel) -> DataDump? {
        guard let storeURL, FileManager.default.fileExists(atPath: storeURL.path) else {
            return nil
        }

        do {
            let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: storeURL, options: nil)
            if managedObjectModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata) {
                return nil
            }
        } catch {
        }

        guard let legacyModel = loadLegacyModel() else {
            return nil
        }

        do {
            let dump = try extractData(from: storeURL, model: legacyModel)
            try archiveLegacyStore(at: storeURL)
            return dump
        } catch {
            return nil
        }
    }

    static func importDump(_ dump: DataDump, into container: NSPersistentCloudKitContainer) async throws {
        try await container.performBackgroundTask { context in
            dump.parsedEntries.forEach { legacy in
                let entry = ParsedEntry(context: context)
                entry.id = legacy.id
                entry.originalText = legacy.originalText
                entry.intent = legacy.intent
                entry.object = legacy.object
                entry.reminderDay = legacy.reminderDay
                entry.reminderTime = legacy.reminderTime
                entry.eventDay = legacy.eventDay
                entry.eventTime = legacy.eventTime
                entry.currency = legacy.currency
                entry.amount = legacy.amount ?? 0
                entry.duration = legacy.duration ?? 0
                entry.distance = legacy.distance ?? 0
                entry.mealQuantity = legacy.mealQuantity
                entry.mealKcal = legacy.mealKcal ?? 0
                entry.source = legacy.source
                entry.createdAt = legacy.createdAt
                entry.modifiedAt = legacy.createdAt
                entry.deviceId = legacy.deviceId
            }

            dump.workSessions.forEach { legacy in
                let session = WorkSession(context: context)
                session.id = legacy.id
                session.date = legacy.date ?? legacy.createdAt ?? Date()
                session.createdAt = legacy.createdAt ?? legacy.date ?? Date()
                session.modifiedAt = session.createdAt
                session.object = legacy.object
                session.durationMinutes = Int32(legacy.durationMinutes ?? 0)
                session.deviceId = legacy.deviceId ?? UUID()
                session.startTime = legacy.startTime ?? "00:00"
                session.endTime = legacy.endTime
            }

            dump.variables.forEach { legacy in
                let variable = VariableEntity(context: context)
                variable.id = legacy.id
                variable.name = legacy.name ?? ""
                variable.type = legacy.type ?? "expense"
                variable.value = legacy.value ?? ""
                variable.currency = legacy.currency
                let created = legacy.createdAt ?? Date()
                variable.createdAt = created
                variable.modifiedAt = created
            }

            dump.reminderTags.forEach { legacy in
                let tag = ReminderEventTag(context: context)
                tag.id = legacy.id
                tag.tag = legacy.tag ?? ""
                tag.colorName = legacy.colorName ?? SimpleTagStore.getColorForTag(legacy.tag ?? "")
                tag.lineId = legacy.lineId
                tag.eventIdentifier = legacy.eventIdentifier
                tag.reminderIdentifier = legacy.reminderIdentifier
                let now = Date()
                tag.createdAt = now
                tag.modifiedAt = now
            }

            dump.calorieCache.forEach { legacy in
                let cache = CalorieLookupCache(context: context)
                cache.id = legacy.id
                cache.foodName = legacy.foodName ?? ""
                cache.calories = legacy.calories ?? 0
                cache.quantityDescriptor = legacy.quantityDescriptor
                cache.isMenu = legacy.isMenu
                cache.sourcesJSON = legacy.sourcesJSON
                let updated = legacy.updatedAt ?? Date()
                cache.updatedAt = updated
                cache.modifiedAt = updated
            }

            dump.currencySettings.forEach { legacy in
                let settings = CurrencySettings(context: context)
                settings.id = legacy.id
                settings.baseCurrency = legacy.baseCurrency ?? "USD"
                settings.lastUpdated = legacy.lastUpdated
                let updated = legacy.lastUpdated ?? Date()
                settings.modifiedAt = updated
            }

            dump.userProfiles.forEach { legacy in
                let profile = UserProfileEntity(context: context)
                profile.id = legacy.id
                profile.heightCm = legacy.height ?? 0
                profile.weightKg = legacy.weight ?? 0
                profile.age = Int32(legacy.age ?? 0)
                profile.biologicalSex = legacy.biologicalSex
                profile.lastHealthSync = legacy.lastHealthSync
                let now = Date()
                profile.modifiedAt = now
            }

            if context.hasChanges {
                try context.save()
            }
        }
    }
}

private extension LegacyStoreMigrator {
    static func loadLegacyModel() -> NSManagedObjectModel? {
        guard let url = Bundle.main.url(forResource: "Mneme 1", withExtension: "mom", subdirectory: "Mneme.momd") else {
            return nil
        }
        return NSManagedObjectModel(contentsOf: url)
    }

    static func extractData(from storeURL: URL, model: NSManagedObjectModel) throws -> DataDump {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let options: [AnyHashable: Any] = [NSReadOnlyPersistentStoreOption: true]
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: options)
        defer { try? coordinator.remove(store) }

        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        let parsedEntries = try fetchParsedEntries(in: context)
        let workSessions = try fetchWorkSessions(in: context)
        let variables = try fetchVariables(in: context)
        let reminderTags = try fetchReminderTags(in: context)
        let calorieEntries = try fetchCalorieCache(in: context)
        let currencySettings = try fetchCurrencySettings(in: context)
        let userProfiles = try fetchUserProfiles(in: context)

        return DataDump(
            parsedEntries: parsedEntries,
            workSessions: workSessions,
            variables: variables,
            reminderTags: reminderTags,
            calorieCache: calorieEntries,
            currencySettings: currencySettings,
            userProfiles: userProfiles
        )
    }

    static func fetchParsedEntries(in context: NSManagedObjectContext) throws -> [LegacyParsedEntry] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "ParsedEntry")
        return try context.fetch(request).map { object in
            let reminderDay = DateHelper.absoluteDayString(from: object.value(forKey: "reminderDay") as? Date)
            let reminderTime = timeString(from: object.value(forKey: "reminderTime") as? Date)
            let eventDay = DateHelper.absoluteDayString(from: object.value(forKey: "eventDay") as? Date)
            let eventTime = timeString(from: object.value(forKey: "eventTime") as? Date)
            let created = (object.value(forKey: "createdAt") as? Date) ?? Date()
            let deviceIdString = object.value(forKey: "deviceId") as? String
            return LegacyParsedEntry(
                id: object.value(forKey: "id") as? UUID ?? UUID(),
                originalText: object.value(forKey: "originalText") as? String ?? "",
                intent: object.value(forKey: "intent") as? String,
                object: object.value(forKey: "object") as? String,
                reminderDay: reminderDay,
                reminderTime: reminderTime,
                eventDay: eventDay,
                eventTime: eventTime,
                currency: object.value(forKey: "currency") as? String,
                amount: object.value(forKey: "amount") as? Double,
                duration: object.value(forKey: "duration") as? Double,
                distance: object.value(forKey: "distance") as? Double,
                mealQuantity: object.value(forKey: "mealQuantity") as? String,
                mealKcal: object.value(forKey: "mealKcal") as? Double,
                source: object.value(forKey: "source") as? String,
                createdAt: created,
                deviceId: UUID(uuidString: deviceIdString ?? "") ?? UUID()
            )
        }
    }

    static func fetchWorkSessions(in context: NSManagedObjectContext) throws -> [LegacyWorkSession] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "WorkSession")
        return try context.fetch(request).map { object in
            LegacyWorkSession(
                id: object.value(forKey: "id") as? UUID ?? UUID(),
                date: object.value(forKey: "date") as? Date,
                startTime: timeString(from: object.value(forKey: "startTime") as? Date),
                endTime: timeString(from: object.value(forKey: "endTime") as? Date),
                object: object.value(forKey: "object") as? String,
                durationMinutes: (object.value(forKey: "durationMinutes") as? NSNumber)?.intValue,
                createdAt: object.value(forKey: "createdAt") as? Date,
                deviceId: UUID(uuidString: (object.value(forKey: "deviceId") as? String ?? ""))
            )
        }
    }

    static func fetchVariables(in context: NSManagedObjectContext) throws -> [LegacyVariable] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Variable")
        return try context.fetch(request).map { object in
            LegacyVariable(
                id: object.value(forKey: "id") as? UUID ?? UUID(),
                name: object.value(forKey: "name") as? String,
                type: object.value(forKey: "type") as? String,
                value: object.value(forKey: "value") as? String,
                currency: object.value(forKey: "currency") as? String,
                createdAt: object.value(forKey: "createdAt") as? Date
            )
        }
    }

    static func fetchReminderTags(in context: NSManagedObjectContext) throws -> [LegacyReminderTag] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "ReminderEventTag")
        return try context.fetch(request).map { object in
            LegacyReminderTag(
                id: object.value(forKey: "id") as? UUID ?? UUID(),
                tag: object.value(forKey: "tag") as? String,
                colorName: object.value(forKey: "colorName") as? String,
                lineId: object.value(forKey: "lineId") as? UUID,
                eventIdentifier: object.value(forKey: "eventIdentifier") as? String,
                reminderIdentifier: object.value(forKey: "reminderIdentifier") as? String
            )
        }
    }

    static func fetchCalorieCache(in context: NSManagedObjectContext) throws -> [LegacyCalorieCache] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CalorieLookupCache")
        return try context.fetch(request).map { object in
            LegacyCalorieCache(
                id: object.value(forKey: "id") as? UUID ?? UUID(),
                foodName: object.value(forKey: "foodName") as? String,
                calories: object.value(forKey: "calories") as? Double,
                quantityDescriptor: object.value(forKey: "quantityDescriptor") as? String,
                isMenu: (object.value(forKey: "isMenu") as? NSNumber)?.boolValue ?? false,
                sourcesJSON: object.value(forKey: "sourcesJSON") as? String,
                updatedAt: object.value(forKey: "updatedAt") as? Date
            )
        }
    }

    static func fetchCurrencySettings(in context: NSManagedObjectContext) throws -> [LegacyCurrencySetting] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CurrencySettings")
        return try context.fetch(request).map { object in
            LegacyCurrencySetting(
                id: object.value(forKey: "id") as? UUID ?? UUID(),
                baseCurrency: object.value(forKey: "baseCurrency") as? String,
                lastUpdated: object.value(forKey: "lastUpdated") as? Date
            )
        }
    }

    static func fetchUserProfiles(in context: NSManagedObjectContext) throws -> [LegacyUserProfile] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "UserProfile")
        return try context.fetch(request).map { object in
            LegacyUserProfile(
                id: object.value(forKey: "id") as? UUID ?? UUID(),
                height: object.value(forKey: "heightCm") as? Double,
                weight: object.value(forKey: "weightKg") as? Double,
                age: (object.value(forKey: "age") as? NSNumber)?.intValue,
                biologicalSex: object.value(forKey: "biologicalSex") as? String,
                lastHealthSync: object.value(forKey: "lastHealthSync") as? Date
            )
        }
    }

    static func archiveLegacyStore(at storeURL: URL) throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let backupURL = storeURL.deletingLastPathComponent().appendingPathComponent("Mneme.Legacy.\(timestamp).sqlite")
        try? FileManager.default.removeItem(at: backupURL)
        try FileManager.default.moveItem(at: storeURL, to: backupURL)

        for suffix in ["-shm", "-wal"] {
            let legacyURL = storeURL.deletingLastPathComponent().appendingPathComponent(storeURL.lastPathComponent + suffix)
            if FileManager.default.fileExists(atPath: legacyURL.path) {
                let backup = backupURL.deletingLastPathComponent().appendingPathComponent(backupURL.lastPathComponent + suffix)
                try? FileManager.default.removeItem(at: backup)
                try FileManager.default.moveItem(at: legacyURL, to: backup)
            }
        }
    }

    static func timeString(from date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
