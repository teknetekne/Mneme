import Foundation
import Combine
import CoreData

struct ParsedNotepadEntry: Identifiable, Equatable {
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
    
    init(
        id: UUID = UUID(),
        date: Date,
        originalText: String,
        intent: String? = nil,
        object: String? = nil,
        reminderTime: String? = nil,
        reminderDay: String? = nil,
        eventTime: String? = nil,
        eventDay: String? = nil,
        currency: String? = nil,
        amount: Double? = nil,
        duration: Double? = nil,
        distance: Double? = nil,
        mealQuantity: String? = nil,
        mealKcal: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.originalText = originalText
        self.intent = intent
        self.object = object
        self.reminderTime = reminderTime
        self.reminderDay = reminderDay
        self.eventTime = eventTime
        self.eventDay = eventDay
        self.currency = currency
        self.amount = amount
        self.duration = duration
        self.distance = distance
        self.mealQuantity = mealQuantity
        self.mealKcal = mealKcal
    }
    
    static func from(parsedResult: ParsedResult, originalText: String, date: Date = Date()) -> ParsedNotepadEntry {
        return ParsedNotepadEntry(
            date: date,
            originalText: originalText,
            intent: parsedResult.intent?.value,
            object: parsedResult.object?.value,
            reminderTime: parsedResult.reminderTime?.value,
            reminderDay: parsedResult.reminderDay?.value,
            eventTime: parsedResult.eventTime?.value,
            eventDay: parsedResult.eventDay?.value,
            currency: parsedResult.currency?.value,
            amount: parsedResult.amount?.value,
            duration: parsedResult.duration?.value,
            distance: parsedResult.distance?.value,
            mealQuantity: parsedResult.mealQuantity?.value,
            mealKcal: parsedResult.mealKcal?.value
        )
    }
    
    init(from entity: ParsedEntry) {
        self.id = entity.id ?? UUID()
        self.date = entity.createdAt ?? Date()
        self.originalText = entity.originalText ?? ""
        self.intent = entity.intent
        self.object = entity.object
        self.reminderTime = entity.reminderTime
        self.reminderDay = entity.reminderDay
        self.eventTime = entity.eventTime
        self.eventDay = entity.eventDay
        self.currency = entity.currency
        self.amount = entity.amount != 0 ? entity.amount : nil
        self.duration = entity.duration != 0 ? entity.duration : nil
        self.distance = entity.distance != 0 ? entity.distance : nil
        self.mealQuantity = entity.mealQuantity
        self.mealKcal = entity.mealKcal != 0 ? entity.mealKcal : nil
    }
}

final class NotepadEntryStore: NSObject, ObservableObject {
    static let shared = NotepadEntryStore()
    
    @Published private(set) var entries: [ParsedNotepadEntry] = []
    
    private var fetchedResultsController: NSFetchedResultsController<ParsedEntry>?
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
            await MainActor.run { self.refreshEntries() }
        }
    }
    
    private func setupFetchedResultsController() {
        let fetchRequest: NSFetchRequest<ParsedEntry> = ParsedEntry.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ParsedEntry.createdAt, ascending: false)]
        
        fetchedResultsController = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        
        fetchedResultsController?.delegate = self
        
        do {
            try fetchedResultsController?.performFetch()
            refreshEntries()
        } catch {
        }
    }
    
    @MainActor
    private func refreshEntries() {
        guard let fetchedObjects = fetchedResultsController?.fetchedObjects else {
            entries = []
            return
        }
        entries = fetchedObjects.map { ParsedNotepadEntry(from: $0) }
    }
    
    @MainActor
    func deleteEntry(_ entry: ParsedNotepadEntry) {
        Task {
            try? await persistence.performBackgroundTask { context in
                let fetchRequest: NSFetchRequest<ParsedEntry> = ParsedEntry.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", entry.id as CVarArg)
                
                if let results = try? context.fetch(fetchRequest), let entity = results.first {
                    context.delete(entity)
                }
                return ()
            }
            // Notify listeners to update immediately
            NotificationCenter.default.post(name: .notepadEntryDeleted, object: nil)
        }
    }
    
    @MainActor
    func addEntry(_ entry: ParsedNotepadEntry) {
        Task {
            try? await persistence.performBackgroundTask { context in
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
                parsedEntry.modifiedAt = Date()
                parsedEntry.deviceId = self.getOrCreateDeviceId()
                return ()
            }
        }
    }
    
    func getEntries(for date: Date) -> [ParsedNotepadEntry] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        
        return entries.filter { entry in
            entry.date >= dayStart && entry.date < dayEnd
        }
    }
    
    func getEntriesCount(for date: Date) -> Int {
        return getEntries(for: date).count
    }
    
    func getNotesPreview(for date: Date, maxLength: Int = 100) -> String {
        let dayEntries = getEntries(for: date)
        let texts = dayEntries.map { $0.originalText }
        let combined = texts.joined(separator: " • ")
        
        if combined.count <= maxLength {
            return combined
        }
        
        return String(combined.prefix(maxLength)) + "..."
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

extension NotepadEntryStore: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        Task { @MainActor in
            refreshEntries()
        }
    }
}
extension Notification.Name {
    static let notepadEntryDeleted = Notification.Name("NotepadEntryDeleted")
}
