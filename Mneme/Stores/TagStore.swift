import Foundation
import CoreData
import SwiftUI
import Combine
import CryptoKit

// MARK: - Tag Model

struct Tag: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let colorName: String
    var createdAt: Date
    var modifiedAt: Date
    
    init(id: UUID = UUID(), name: String, colorName: String, createdAt: Date = Date(), modifiedAt: Date = Date()) {
        self.id = id
        self.name = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        self.colorName = colorName
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
    }
    
    var color: Color {
        TagStore.color(from: colorName)
    }
    
    var displayName: String {
        name.capitalized
    }
}

// MARK: - Tag Store

@MainActor
final class TagStore: NSObject, ObservableObject {
    static let shared = TagStore(persistence: PersistenceController.shared)
    private static let defaultsSeededKey = "TagStoreDefaultsSeeded"
    
    @Published private(set) var allTags: [Tag] = []
    @Published private(set) var tagAssignments: [UUID: Set<UUID>] = [:]
    
    private let persistence: Persistence
    private var tagController: NSFetchedResultsController<NSManagedObject>?
    private var assignmentController: NSFetchedResultsController<NSManagedObject>?
    
    static let availableColors: [(name: String, color: Color)] = [
        ("red", .red),
        ("blue", .blue),
        ("green", .green),
        ("yellow", .yellow),
        ("purple", .purple),
        ("orange", .orange),
        ("pink", .pink),
        ("gray", .gray)
    ]
    
    private static let defaultTags: [(name: String, color: String)] = [
        ("work", "red"),
        ("personal", "blue"),
        ("family", "yellow"),
        ("health", "green"),
        ("education", "purple")
    ]
    
    private init(persistence: Persistence) {
        self.persistence = persistence
        super.init()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.setupControllers()
            self.ensureDefaultTags()
        }
    }
    
    // MARK: - Setup
    
    private func setupControllers() {
        setupTagController()
        setupAssignmentController()
    }
    
    private func setupTagController() {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TagEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        
        let controller = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: persistence.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        controller.delegate = self
        tagController = controller
        
        do {
            try controller.performFetch()
            updateTagsCache()
        } catch {
        }
    }
    
    private func setupAssignmentController() {
        let request = NSFetchRequest<NSManagedObject>(entityName: "TagAssignment")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        let controller = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: persistence.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        controller.delegate = self
        assignmentController = controller
        
        do {
            try controller.performFetch()
            updateAssignmentsCache()
        } catch {
        }
    }
    
    private func ensureDefaultTags() {
        Task {
            let defaultsKey = Self.defaultsSeededKey
            let defaults = UserDefaults.standard
            guard !defaults.bool(forKey: defaultsKey) else { return }
            
            do {
                try await persistence.performBackgroundTask { context in
                    let countRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "TagEntity")
                    countRequest.includesSubentities = false
                    let existingCount = try context.count(for: countRequest)
                    guard existingCount == 0 else { return }
                    
                    for (name, color) in Self.defaultTags {
                        let entity = NSEntityDescription.insertNewObject(forEntityName: "TagEntity", into: context)
                        entity.setValue(UUID(), forKey: "id")
                        entity.setValue(name, forKey: "name")
                        entity.setValue(color, forKey: "colorName")
                        let now = Date()
                        entity.setValue(now, forKey: "createdAt")
                        entity.setValue(now, forKey: "modifiedAt")
                    }
                    
                    if context.hasChanges {
                        try context.save()
                    }
                }
                defaults.set(true, forKey: defaultsKey)
            } catch {
            }
        }
    }
    
    // MARK: - Cache Updates
    
    private func updateTagsCache() {
        guard let entities = tagController?.fetchedObjects else {
            allTags = []
            return
        }
        let tags = entities.compactMap { entity -> Tag? in
            guard let id = entity.value(forKey: "id") as? UUID,
                  let name = entity.value(forKey: "name") as? String,
                  let colorName = entity.value(forKey: "colorName") as? String,
                  let createdAt = entity.value(forKey: "createdAt") as? Date,
                  let modifiedAt = entity.value(forKey: "modifiedAt") as? Date else {
                return nil
            }
            return Tag(id: id, name: name, colorName: colorName, createdAt: createdAt, modifiedAt: modifiedAt)
        }
        allTags = tags.sorted { $0.name < $1.name }
    }
    
    private func updateAssignmentsCache() {
        guard let assignments = assignmentController?.fetchedObjects else {
            tagAssignments = [:]
            return
        }
        
        var mapping: [UUID: Set<UUID>] = [:]
        for assignment in assignments {
            guard let targetId = assignment.value(forKey: "targetId") as? UUID,
                  let tagId = assignment.value(forKey: "tagId") as? UUID else {
                continue
            }
            mapping[targetId, default: []].insert(tagId)
        }
        tagAssignments = mapping
    }
    
    // MARK: - Public API - Tags
    
    func getAllTags() -> [Tag] {
        if allTags.isEmpty {
            return Self.defaultTags.map { Tag(name: $0.name, colorName: $0.color) }
        }
        return allTags
    }
    
    func getTag(byId id: UUID) -> Tag? {
        allTags.first { $0.id == id }
    }
    
    func getTag(byName name: String) -> Tag? {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return allTags.first { $0.name == normalized }
    }
    
    func createTag(name: String, colorName: String? = nil) async throws {
        let normalized = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        
        let color = colorName ?? Self.colorForTag(normalized)
        
        try await persistence.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "TagEntity")
            request.predicate = NSPredicate(format: "name ==[c] %@", normalized)
            request.fetchLimit = 1
            
            if try context.fetch(request).isEmpty {
                let entity = NSEntityDescription.insertNewObject(forEntityName: "TagEntity", into: context)
                entity.setValue(UUID(), forKey: "id")
                entity.setValue(normalized, forKey: "name")
                entity.setValue(color, forKey: "colorName")
                let now = Date()
                entity.setValue(now, forKey: "createdAt")
                entity.setValue(now, forKey: "modifiedAt")
            }
        }
    }
    
    func updateTag(id: UUID, newName: String? = nil, newColorName: String? = nil) async throws {
        try await persistence.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "TagEntity")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            
            guard let entity = try context.fetch(request).first else { return }
            
            if let newName = newName {
                let normalized = newName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                if !normalized.isEmpty {
                    entity.setValue(normalized, forKey: "name")
                }
            }
            
            if let newColorName = newColorName {
                entity.setValue(newColorName, forKey: "colorName")
            }
            
            entity.setValue(Date(), forKey: "modifiedAt")
        }
    }
    
    func deleteTag(id: UUID) async throws {
        try await persistence.performBackgroundTask { context in
            let tagRequest = NSFetchRequest<NSManagedObject>(entityName: "TagEntity")
            tagRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            
            guard let tagEntity = try context.fetch(tagRequest).first else { return }
            
            let assignmentRequest = NSFetchRequest<NSManagedObject>(entityName: "TagAssignment")
            assignmentRequest.predicate = NSPredicate(format: "tagId == %@", id as CVarArg)
            let assignments = try context.fetch(assignmentRequest)
            
            for assignment in assignments {
                context.delete(assignment)
            }
            
            context.delete(tagEntity)
        }
    }
    
    // MARK: - Public API - Assignments
    
    func getTags(for targetId: UUID) -> [Tag] {
        guard let tagIds = tagAssignments[targetId], !tagIds.isEmpty else { return [] }
        
        let tags = tagIds.compactMap { getTag(byId: $0) }
        return tags.sorted { $0.name < $1.name }
    }
    
    func getUnassignedTags(for targetId: UUID) -> [Tag] {
        let assignedIds = tagAssignments[targetId] ?? []
        return allTags.filter { !assignedIds.contains($0.id) }
    }
    
    func assignTag(_ tagId: UUID, to targetId: UUID) async throws {
        try await persistence.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "TagAssignment")
            request.predicate = NSPredicate(format: "tagId == %@ AND targetId == %@", tagId as CVarArg, targetId as CVarArg)
            request.fetchLimit = 1
            
            if try context.fetch(request).isEmpty {
                let assignment = NSEntityDescription.insertNewObject(forEntityName: "TagAssignment", into: context)
                assignment.setValue(UUID(), forKey: "id")
                assignment.setValue(tagId, forKey: "tagId")
                assignment.setValue(targetId, forKey: "targetId")
                assignment.setValue(Date(), forKey: "createdAt")
            }
        }
    }
    
    func unassignTag(_ tagId: UUID, from targetId: UUID) async throws {
        try await persistence.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "TagAssignment")
            request.predicate = NSPredicate(format: "tagId == %@ AND targetId == %@", tagId as CVarArg, targetId as CVarArg)
            
            if let assignment = try context.fetch(request).first {
                context.delete(assignment)
            }
        }
    }
    
    func assignTagByName(_ tagName: String, to targetId: UUID, colorName: String? = nil) async throws {
        let normalized = tagName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        
        if let existingTag = getTag(byName: normalized) {
            try await assignTag(existingTag.id, to: targetId)
        } else {
            let color = colorName ?? Self.colorForTag(normalized)
            try await persistence.performBackgroundTask { context in
                let tagEntity = NSEntityDescription.insertNewObject(forEntityName: "TagEntity", into: context)
                let tagId = UUID()
                tagEntity.setValue(tagId, forKey: "id")
                tagEntity.setValue(normalized, forKey: "name")
                tagEntity.setValue(color, forKey: "colorName")
                let now = Date()
                tagEntity.setValue(now, forKey: "createdAt")
                tagEntity.setValue(now, forKey: "modifiedAt")
                
                let assignment = NSEntityDescription.insertNewObject(forEntityName: "TagAssignment", into: context)
                assignment.setValue(UUID(), forKey: "id")
                assignment.setValue(tagId, forKey: "tagId")
                assignment.setValue(targetId, forKey: "targetId")
                assignment.setValue(now, forKey: "createdAt")
            }
        }
    }
    
    func clearTags(for targetId: UUID) async throws {
        try await persistence.performBackgroundTask { context in
            let request = NSFetchRequest<NSManagedObject>(entityName: "TagAssignment")
            request.predicate = NSPredicate(format: "targetId == %@", targetId as CVarArg)
            
            let assignments = try context.fetch(request)
            for assignment in assignments {
                context.delete(assignment)
            }
        }
    }
    
    // MARK: - Legacy Support (for Reminder/Event identifiers)
    
    func getTags(forReminderIdentifier identifier: String) -> [Tag] {
        let targetId = Self.stableUUID(for: identifier)
        return getTags(for: targetId)
    }
    
    func getTags(forEventIdentifier identifier: String) -> [Tag] {
        let targetId = Self.stableUUID(for: identifier)
        return getTags(for: targetId)
    }
    
    func commitTags(from lineId: UUID, toReminderIdentifier reminderId: String) async throws {
        let targetId = Self.stableUUID(for: reminderId)
        let tags = getTags(for: lineId)
        for tag in tags {
            try await assignTag(tag.id, to: targetId)
        }
        try await clearTags(for: lineId)
    }
    
    func commitTags(from lineId: UUID, toEventIdentifier eventId: String) async throws {
        let targetId = Self.stableUUID(for: eventId)
        let tags = getTags(for: lineId)
        for tag in tags {
            try await assignTag(tag.id, to: targetId)
        }
        try await clearTags(for: lineId)
    }
    
    // MARK: - Static Helpers
    
    static func colorForTag(_ tagName: String) -> String {
        let lower = tagName.lowercased()
        if let defaultTag = defaultTags.first(where: { $0.name == lower }) {
            return defaultTag.color
        }
        let hash = abs(lower.hashValue)
        return availableColors[hash % availableColors.count].name
    }
    
    static func color(from colorName: String) -> Color {
        availableColors.first(where: { $0.name == colorName })?.color ?? .red
    }
    
    static func defaultColor() -> String {
        availableColors[0].name
    }
    
    static func stableUUID(for identifier: String) -> UUID {
        if let uuid = UUID(uuidString: identifier) {
            return uuid
        }
        let bytes = stableBytes(for: identifier)
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
    
    private static func stableBytes(for identifier: String) -> [UInt8] {
        let data = Data(("mneme-tag-" + identifier).utf8)
        let hash = SHA256.hash(data: data)
        return Array(hash.prefix(16))
    }
}

// MARK: - NSFetchedResultsControllerDelegate

extension TagStore: NSFetchedResultsControllerDelegate {
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        if controller === tagController {
            updateTagsCache()
        } else if controller === assignmentController {
            updateAssignmentsCache()
        }
    }
}
