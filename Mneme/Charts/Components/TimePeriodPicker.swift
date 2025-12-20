import SwiftUI

/// Reusable time period picker for charts
struct TimePeriodPicker: View {
    @Binding var selection: ChartTimePeriod
    var accentColor: Color = .blue
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(ChartTimePeriod.allCases) { period in
                periodButton(period)
            }
        }
        .padding(4)
        .background(pickerBackground)
        .clipShape(Capsule())
    }
    
    private func periodButton(_ period: ChartTimePeriod) -> some View {
        Button {
            #if os(iOS)
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            #endif
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selection = period
            }
        } label: {
            Text(period.title)
                .font(.system(size: 13, weight: selection == period ? .semibold : .medium))
                .foregroundStyle(selection == period ? .white : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Group {
                        if selection == period {
                            Capsule()
                                .fill(accentColor)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }
    
    private var pickerBackground: some ShapeStyle {
        colorScheme == .dark 
            ? AnyShapeStyle(Color.white.opacity(0.08))
            : AnyShapeStyle(Color.black.opacity(0.05))
    }
}

#Preview {
    VStack(spacing: 20) {
        TimePeriodPicker(selection: .constant(.day), accentColor: .blue)
        TimePeriodPicker(selection: .constant(.week), accentColor: .orange)
        TimePeriodPicker(selection: .constant(.month), accentColor: .green)
    }
    .padding()
}
