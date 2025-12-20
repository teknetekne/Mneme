import Foundation
import CoreData
import CloudKit

protocol Persistence {
    var viewContext: NSManagedObjectContext { get }
    func newBackgroundContext() -> NSManagedObjectContext
    func save() throws
    func save(context: NSManagedObjectContext) throws
    @discardableResult
    func performBackgroundTask<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T
}

/// CloudKit-mirrored Core Data stack used in production.
final class PersistenceController: Persistence {
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    /// Note: CloudKit push requires the 'remote-notification' background mode in Info.plist.
    /// When not available or iCloud is misconfigured, we fall back to a local Core Data store.
    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Mneme")

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve persistent store description")
        }

        // Use in-memory store when requested (tests, previews)
        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        }

        // History + remote change notifications for live updates
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // CloudKit mirroring (enable only when available)
        let cloudIdentifier = Bundle.main.object(forInfoDictionaryKey: "iCloudContainerIdentifier") as? String
        let isSignedIntoICloud = FileManager.default.ubiquityIdentityToken != nil
        
        if let containerID = cloudIdentifier,
           !containerID.isEmpty,
           isSignedIntoICloud {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: containerID
            )
        }

        let legacyDump: LegacyStoreMigrator.DataDump?
        if inMemory {
            legacyDump = nil
        } else {
            legacyDump = LegacyStoreMigrator.prepareMigrationIfNeeded(
                storeURL: description.url,
                managedObjectModel: container.managedObjectModel
            )
        }

        container.persistentStoreDescriptions = [description]

        var attemptedLocalFallback = false

        func loadStore() {
            container.loadPersistentStores { _, error in
                if let error = error {
                    if !attemptedLocalFallback {
                        attemptedLocalFallback = true
                        description.cloudKitContainerOptions = nil
                        self.container.persistentStoreDescriptions = [description]
                        loadStore()
                    } else {
                        fatalError("Core Data store failed to load even locally: \(error.localizedDescription)")
                    }
                }
            }
        }

        loadStore()

        // Merge changes coming from background contexts & CloudKit
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Tweak undo + concurrency for UI responsiveness
        container.viewContext.undoManager = nil
        container.viewContext.shouldDeleteInaccessibleFaults = true

        if let dump = legacyDump {
            Task.detached { [container] in
                do {
                    try await LegacyStoreMigrator.importDump(dump, into: container)
                } catch {
                }
            }
        }
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        return context
    }

    func save() throws {
        let context = container.viewContext
        if context.hasChanges {
            try context.save()
        }
    }

    func save(context: NSManagedObjectContext) throws {
        if context.hasChanges {
            try context.save()
        }
    }

    @discardableResult
    func performBackgroundTask<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            container.performBackgroundTask { context in
                context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                do {
                    let result = try block(context)
                    if context.hasChanges {
                        try context.save()
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Lightweight in-memory persistence for previews/tests or local-only mode.
final class InMemoryPersistence: Persistence {
    let container: NSPersistentContainer

    init() {
        container = NSPersistentContainer(name: "Mneme")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("In-memory store failed to load: \(error)")
            }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    var viewContext: NSManagedObjectContext { container.viewContext }

    func newBackgroundContext() -> NSManagedObjectContext {
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return ctx
    }

    func save() throws {
        if viewContext.hasChanges { try viewContext.save() }
    }

    func save(context: NSManagedObjectContext) throws {
        if context.hasChanges { try context.save() }
    }

    @discardableResult
    func performBackgroundTask<T>(_ block: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let ctx = self.newBackgroundContext()
            ctx.perform {
                do {
                    let result = try block(ctx)
                    if ctx.hasChanges { try ctx.save() }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
