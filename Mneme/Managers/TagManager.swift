import Foundation
import Combine

// MARK: - Tag Manager

/// Manages tag operations for notepad lines
/// Responsibility: Wrapper around TagStore with line-specific tag operations
@MainActor
final class TagManager: ObservableObject {
    
    // MARK: - Dependencies
    
    let tagStore: TagStore
    
    // MARK: - Initialization
    
    init(tagStore: TagStore? = nil) {
        self.tagStore = tagStore ?? .shared
    }
    
    // MARK: - Tag Queries
    
    /// Get all tags assigned to a specific line
    /// - Parameter lineId: UUID of the line
    /// - Returns: Array of Tag objects
    func getTags(for lineId: UUID) -> [Tag] {
        tagStore.getTags(for: lineId)
    }
    
    /// Get all available tags that are NOT assigned to a specific line
    /// - Parameter lineId: UUID of the line
    /// - Returns: Array of unassigned Tag objects
    func getUnaddedTags(for lineId: UUID) -> [Tag] {
        tagStore.getUnassignedTags(for: lineId)
    }
    
    /// Get all tags in the system
    /// - Returns: Array of all Tag objects
    func getAllTags() -> [Tag] {
        tagStore.allTags
    }
    
    // MARK: - Tag Assignment
    
    /// Add a tag to a line (create if doesn't exist)
    /// - Parameters:
    ///   - lineId: UUID of the line
    ///   - tagName: Name of the tag
    ///   - colorName: Optional color name (Theme.TagColor)
    func addTag(to lineId: UUID, tagName: String, colorName: String? = nil) async throws {
        try await tagStore.assignTagByName(tagName, to: lineId)
    }
    
    /// Remove a tag from a line
    /// - Parameters:
    ///   - lineId: UUID of the line
    ///   - tag: Tag object to remove
    func removeTag(from lineId: UUID, tag: Tag) async throws {
        try await tagStore.unassignTag(tag.id, from: lineId)
    }
    
    // MARK: - Tag Management
    
    /// Create a new tag in the system
    /// - Parameters:
    ///   - name: Tag name
    ///   - colorName: Color name (Theme.TagColor)
    /// - Returns: Created Tag object
    @discardableResult
    func createTag(name: String, colorName: String) async throws -> Tag {
        try await tagStore.createTag(name: name, colorName: colorName)
        // Return the created tag
        return tagStore.getTag(byName: name) ?? Tag(name: name, colorName: colorName)
    }
    
    /// Update an existing tag
    /// - Parameters:
    ///   - tag: Tag to update
    ///   - newName: New name
    ///   - newColorName: New color name
    func updateTag(_ tag: Tag, newName: String, newColorName: String) async throws {
        try await tagStore.updateTag(id: tag.id, newName: newName, newColorName: newColorName)
    }
    
    /// Delete a tag from the system
    /// - Parameter tag: Tag to delete
    func deleteTag(_ tag: Tag) async throws {
        try await tagStore.deleteTag(id: tag.id)
    }
    
    // MARK: - Bulk Operations
    
    /// Remove all tags from a line
    /// - Parameter lineId: UUID of the line
    func removeAllTags(from lineId: UUID) async throws {
        let tags = getTags(for: lineId)
        for tag in tags {
            try await removeTag(from: lineId, tag: tag)
        }
    }
    
    /// Commit tags from lineId to event/reminder identifier
    func commitTags(from lineId: UUID, toEventIdentifier eventId: String) async throws {
        try await tagStore.commitTags(from: lineId, toEventIdentifier: eventId)
    }
    
    func commitTags(from lineId: UUID, toReminderIdentifier reminderId: String) async throws {
        try await tagStore.commitTags(from: lineId, toReminderIdentifier: reminderId)
    }
    
    /// Clear all tags from a line
    func clearTags(for lineId: UUID) async throws {
        try await tagStore.clearTags(for: lineId)
    }
}
