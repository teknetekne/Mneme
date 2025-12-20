import SwiftUI
import Foundation
import Combine
import CoreData

// MARK: - Simple Tag Model

struct SimpleTag: Identifiable, Hashable {
    let id: UUID
    let name: String
    let colorName: String
    
    init(id: UUID = UUID(), name: String, colorName: String) {
        self.id = id
        self.name = name
        self.colorName = colorName
    }
    
    var color: Color {
        SimpleTagStore.getColor(from: colorName)
    }
}

// MARK: - Simple Tag Store

@MainActor
final class SimpleTagStore: NSObject, ObservableObject {
    static let shared = SimpleTagStore(persistence: PersistenceController.shared)
    
    @Published private var lineTags: [UUID: [SimpleTag]] = [:]
    @Published private var reminderTags: [String: [SimpleTag]] = [:]
    @Published private var eventTags: [String: [SimpleTag]] = [:]
    @Published private var catalog: [String: SimpleTag] = [:]
    
    private let persistence: Persistence
    private var fetchedResultsController: NSFetchedResultsController<ReminderEventTag>?
    
    static let availableColors: [(name: String, color: Color)] = [
        ("red", .red), ("blue", .blue), ("green", .green), ("yellow", .yellow),
        ("purple", .purple), ("orange", .orange), ("pink", .pink), ("gray", .gray)
    ]
    
    private static let defaultTagColors: [String: String] = [
        "work": "red", "personal": "blue", "family": "yellow",
        "health": "green", "education": "purple"
    ]
    
    private init(persistence: Persistence) {
        self.persistence = persistence
        super.init()
        setupFetchedResultsController()
    }
    
    // MARK: - Fetched Results Controller
    
    private func setupFetchedResultsController() {
        let request: NSFetchRequest<ReminderEventTag> = ReminderEventTag.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ReminderEventTag.modifiedAt, ascending: false)
        ]
        
        let controller = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: persistence.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        controller.delegate = self
        fetchedResultsController = controller
        
        do {
            try controller.performFetch()
            rebuildCaches()
        } catch {
        }
    }
    
    private func rebuildCaches() {
        guard let tags = fetchedResultsController?.fetchedObjects else {
            lineTags = [:]
            reminderTags = [:]
            eventTags = [:]
            catalog = [:]
            return
        }
        
        var lineMapping: [UUID: [SimpleTag]] = [:]
        var reminderMapping: [String: [SimpleTag]] = [:]
        var eventMapping: [String: [SimpleTag]] = [:]
        var all: [String: SimpleTag] = [:]
        
        for entity in tags {
            guard let name = entity.tag?.lowercased(),
                  let colorName = entity.colorName else {
                continue
            }
            let identifier = entity.id ?? UUID()
            let tag = SimpleTag(id: identifier, name: name, colorName: colorName)
            all[name] = tag
            
            if let lineId = entity.lineId {
                lineMapping[lineId, default: []].append(tag)
            }
            if let reminderId = entity.reminderIdentifier {
                reminderMapping[reminderId, default: []].append(tag)
            }
            if let eventId = entity.eventIdentifier {
                eventMapping[eventId, default: []].append(tag)
            }
        }
        
        lineTags = lineMapping
        reminderTags = reminderMapping
        eventTags = eventMapping
        catalog = all
    }
    
    // MARK: - Public API
    
    func getTags(for lineId: UUID) -> [SimpleTag] {
        lineTags[lineId] ?? []
    }
    
    func getTags(forReminderIdentifier identifier: String) -> [SimpleTag] {
        reminderTags[identifier] ?? []
    }
    
    func getTags(forEventIdentifier identifier: String) -> [SimpleTag] {
        eventTags[identifier] ?? []
    }
    
    func getAllTags() -> [SimpleTag] {
        if catalog.isEmpty {
            return Self.defaultTagColors.map { SimpleTag(name: $0.key, colorName: $0.value) }
        }
        return Array(catalog.values).sorted { $0.name < $1.name }
    }
    
    func getUnaddedTags(for lineId: UUID) -> [SimpleTag] {
        let existingNames = Set(getTags(for: lineId).map { $0.name })
        return getAllTags().filter { !existingNames.contains($0.name) }
    }
    
    func getTagColor(for tagName: String) -> Color {
        Self.getColor(from: Self.getColorForTag(tagName))
    }
    
    func addTag(to lineId: UUID, tagName: String, colorName: String? = nil) {
        let normalized = tagName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        let color = colorName ?? Self.getColorForTag(normalized)
        
        Task {
            try? await persistence.performBackgroundTask { context in
                let fetch: NSFetchRequest<ReminderEventTag> = ReminderEventTag.fetchRequest()
                fetch.predicate = NSPredicate(format: "lineId == %@ AND tag ==[c] %@", lineId as CVarArg, normalized)
                fetch.fetchLimit = 1
                
                let now = Date()
                if let existing = try context.fetch(fetch).first {
                    existing.colorName = color
                    existing.modifiedAt = now
                } else {
                    let entity = ReminderEventTag(context: context)
                    entity.id = UUID()
                    entity.lineId = lineId
                    entity.tag = normalized
                    entity.colorName = color
                    entity.createdAt = now
                    entity.modifiedAt = now
                }
            }
        }
    }
    
    func removeTag(from lineId: UUID, tagName: String) {
        let normalized = tagName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        
        Task {
            try? await persistence.performBackgroundTask { context in
                let fetch: NSFetchRequest<ReminderEventTag> = ReminderEventTag.fetchRequest()
                fetch.predicate = NSPredicate(format: "lineId == %@ AND tag ==[c] %@", lineId as CVarArg, normalized)
                if let tag = try context.fetch(fetch).first {
                    context.delete(tag)
                }
            }
        }
    }
    
    func updateTagInDatabase(oldName: String, newName: String, newColor: String? = nil) {
        let oldNormalized = oldName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let newNormalized = newName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !oldNormalized.isEmpty, !newNormalized.isEmpty else { return }
        let color = newColor ?? Self.getColorForTag(newNormalized)
        
        Task {
            try? await persistence.performBackgroundTask { context in
                let fetch: NSFetchRequest<ReminderEventTag> = ReminderEventTag.fetchRequest()
                fetch.predicate = NSPredicate(format: "tag ==[c] %@", oldNormalized)
                let now = Date()
                let tags = try context.fetch(fetch)
                for tag in tags {
                    tag.tag = newNormalized
                    tag.colorName = color
                    tag.modifiedAt = now
                }
            }
        }
    }
    
    func deleteTag(_ tagName: String) {
        let normalized = tagName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return }
        
        Task {
            try? await persistence.performBackgroundTask { context in
                let fetch: NSFetchRequest<ReminderEventTag> = ReminderEventTag.fetchRequest()
                fetch.predicate = NSPredicate(format: "tag ==[c] %@", normalized)
                let tags = try context.fetch(fetch)
                for tag in tags {
                    context.delete(tag)
                }
            }
        }
    }
    
    func clearTags(for lineId: UUID) {
        Task {
            try? await persistence.performBackgroundTask { context in
                let fetch: NSFetchRequest<ReminderEventTag> = ReminderEventTag.fetchRequest()
                fetch.predicate = NSPredicate(format: "lineId == %@", lineId as CVarArg)
                let tags = try context.fetch(fetch)
                for tag in tags where tag.eventIdentifier == nil && tag.reminderIdentifier == nil {
                    context.delete(tag)
                }
            }
        }
    }
    
    func commitTags(for lineId: UUID, reminderIdentifier: String? = nil, eventIdentifier: String? = nil) {
        guard reminderIdentifier != nil || eventIdentifier != nil else { return }
        Task {
            try? await persistence.performBackgroundTask { context in
                let fetch: NSFetchRequest<ReminderEventTag> = ReminderEventTag.fetchRequest()
                fetch.predicate = NSPredicate(format: "lineId == %@", lineId as CVarArg)
                let tags = try context.fetch(fetch)
                guard !tags.isEmpty else { return }
                let now = Date()
                for tag in tags {
                    if let reminderIdentifier {
                        tag.reminderIdentifier = reminderIdentifier
                    }
                    if let eventIdentifier {
                        tag.eventIdentifier = eventIdentifier
                    }
                    tag.lineId = nil
                    tag.modifiedAt = now
                }
            }
        }
    }
    
    // MARK: - Static Helpers
    
    static func getColorForTag(_ tagName: String) -> String {
        let lower = tagName.lowercased()
        if let color = defaultTagColors[lower] {
            return color
        }
        let hash = abs(lower.hashValue)
        return availableColors[hash % availableColors.count].name
    }
    
    static func getColor(from colorName: String) -> Color {
        availableColors.first(where: { $0.name == colorName })?.color ?? .red
    }
    
    static func getDefaultColor() -> String {
        availableColors[0].name
    }
}

extension SimpleTagStore: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        rebuildCaches()
    }
}
