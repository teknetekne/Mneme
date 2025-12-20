import SwiftUI

struct TagPillRow: View {
    let tags: [Tag]
    var font: Font = .caption2
    var maxDisplayed: Int = 5
    
    var body: some View {
        if tags.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                ForEach(tags.prefix(maxDisplayed)) { tag in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(tag.color)
                            .frame(width: 6, height: 6)
                        Text(tag.displayName)
                            .font(font)
                            .foregroundStyle(.primary.opacity(0.8))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tag.color.opacity(0.15))
                    .clipShape(Capsule())
                }
            }
        }
    }
}
