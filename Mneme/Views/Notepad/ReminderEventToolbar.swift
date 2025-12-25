import SwiftUI

struct ReminderEventToolbar: View {
    @Environment(\.colorScheme) private var colorScheme
    let eventId: UUID
    let displayName: String
    let type: String
    let day: String?
    let time: String?
    let tags: [Tag]
    let unaddedTags: [Tag]
    let onAddTag: (String) -> Void
    let onRemoveTag: (Tag) -> Void
    let onAddNewTag: () -> Void
    let onEditTag: (Tag) -> Void
    let onDeleteTag: (Tag) -> Void
    let onAddLocation: () -> Void
    let onEdit: () -> Void

    
    @State private var showDetails = false
    
    private var selectedTagIds: Set<UUID> {
        Set(tags.map(\.id))
    }
    
    private var sortedTags: [Tag] {
        (tags + unaddedTags)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                    Button {
                        withAnimation {
                            showDetails.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(displayName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Image(systemName: showDetails ? "chevron.left" : "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(white: colorScheme == .dark ? 1 : 0, opacity: colorScheme == .dark ? 0.12 : 0.06))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    
                    if showDetails {
                        Button {
                            onEdit()
                        } label: {
                            detailsView
                        }
                        .buttonStyle(.plain)
                    }
                
                ForEach(sortedTags, id: \.id) { tag in
                    let isSelected = selectedTagIds.contains(tag.id)
                    TagChip(
                        tag: tag.displayName,
                        color: tag.color,
                        isSelected: isSelected,
                        onTap: {
                            if isSelected {
                                onRemoveTag(tag)
                            } else {
                                onAddTag(tag.name)
                            }
                        },
                        onEdit: { onEditTag(tag) },
                        onDelete: { onDeleteTag(tag) }
                    )
                }
                
                Button {
                    onAddLocation()
                } label: {
                    locationButtonLabel
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
                
                Button {
                    onAddNewTag()
                } label: {
                    addButtonLabel
                }
                .buttonStyle(.plain)
                .contentShape(Capsule())
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private var detailsView: some View {
        HStack(spacing: 4) {
            if let day = day {
                Text(day)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let time = time {
                Text(time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(white: colorScheme == .dark ? 1 : 0, opacity: colorScheme == .dark ? 0.08 : 0.04))
        .clipShape(Capsule())
    }
    
    private var locationButtonLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "mappin.and.ellipse")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(white: colorScheme == .dark ? 1 : 0, opacity: colorScheme == .dark ? 0.15 : 0.08))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
    }
    
    private var addButtonLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.caption2)
                .fontWeight(.medium)
            Text("Add")
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(white: colorScheme == .dark ? 1 : 0, opacity: colorScheme == .dark ? 0.15 : 0.08))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
    }
}
