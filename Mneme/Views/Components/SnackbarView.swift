import SwiftUI

enum SnackbarStyle {
    case success
    case error
    case warning
    case info
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }
}

struct SnackbarView: View {
    let title: String
    let message: String
    let style: SnackbarStyle
    let onDismiss: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: style.icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(style.color)
            
            VStack(alignment: .leading, spacing: 4) {
                if !title.isEmpty {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(8)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Circle())
            }
        }
        .padding(16)
        .background(
            Material.thin
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        .padding(.horizontal)
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2).ignoresSafeArea()
        
        VStack(spacing: 20) {
            SnackbarView(
                title: "Success",
                message: "Reminder created successfully",
                style: .success,
                onDismiss: {}
            )
            
            SnackbarView(
                title: "Error",
                message: "Failed to connect to server",
                style: .error,
                onDismiss: {}
            )
            
            SnackbarView(
                title: "",
                message: "Simple message without title",
                style: .info,
                onDismiss: {}
            )
        }
    }
}
