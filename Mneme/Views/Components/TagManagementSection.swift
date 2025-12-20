import SwiftUI

struct TagManagementSection: View {
    let title: String
    let targetId: UUID
    
    @EnvironmentObject private var tagStore: TagStore
    @State private var showAddTagSheet = false
    @State private var editingTag: Tag?
    
    private var assignedTagIds: Set<UUID> {
        Set(tagStore.getTags(for: targetId).map(\.id))
    }
    
    private var sortedTags: [Tag] {
        tagStore.getAllTags().sorted { $0.displayName < $1.displayName }
    }
    
    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 120), spacing: 8)]
    }
    
    var body: some View {
        Section(title) {
            if sortedTags.isEmpty {
                Text("No tags yet. Create one to get started.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 8) {
                    ForEach(sortedTags) { tag in
                        let isSelected = assignedTagIds.contains(tag.id)
                        TagChip(
                            tag: tag.displayName,
                            color: tag.color,
                            isSelected: isSelected,
                            onTap: {
                                toggleTag(tag, isSelected: isSelected)
                            },
                            onEdit: {
                                editingTag = tag
                            },
                            onDelete: {
                                deleteTag(tag)
                            }
                        )
                    }
                }
                Text("Tap to toggle. Long-press a tag for edit or delete.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            
            Button {
                showAddTagSheet = true
            } label: {
                Label("New Tag", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showAddTagSheet) {
            AddTagSheet(
                eventId: targetId,
                initialName: "",
                onSave: { name, colorName in
                    attachNewTag(name: name, colorName: colorName)
                    showAddTagSheet = false
                },
                onCancel: {
                    showAddTagSheet = false
                }
            )
        }
        .sheet(item: $editingTag) { tag in
            EditTagSheet(
                eventId: targetId,
                tagId: tag.id,
                currentTag: tag.name,
                currentColorName: tag.colorName,
                onSave: { _, newName, colorName in
                    updateTag(tagId: tag.id, newName: newName, colorName: colorName)
                    editingTag = nil
                },
                onCancel: {
                    editingTag = nil
                }
            )
        }
    }
    
    private func toggleTag(_ tag: Tag, isSelected: Bool) {
        Task {
            do {
                if isSelected {
                    try await tagStore.unassignTag(tag.id, from: targetId)
                } else {
                    try await tagStore.assignTag(tag.id, to: targetId)
                }
            } catch {
            }
        }
    }
    
    private func attachNewTag(name: String, colorName: String) {
        Task {
            do {
                try await tagStore.assignTagByName(name, to: targetId, colorName: colorName)
            } catch {
            }
        }
    }
    
    private func updateTag(tagId: UUID, newName: String, colorName: String) {
        Task {
            do {
                try await tagStore.updateTag(id: tagId, newName: newName, newColorName: colorName)
            } catch {
            }
        }
    }
    
    private func deleteTag(_ tag: Tag) {
        Task {
            do {
                try await tagStore.deleteTag(id: tag.id)
            } catch {
            }
        }
    }
}
