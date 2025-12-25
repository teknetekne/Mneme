import SwiftUI

struct DailySummaryCard: View {
    let summary: DailySummary
    let isExpanded: Bool
    let toggle: () -> Void
    let onManageEntries: (Date) -> Void

    let cornerRadius: CGFloat
    let shadowRadius: CGFloat

    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            header
                .contentShape(Rectangle())
                .onTapGesture(perform: toggle)

            if isExpanded {
                Divider()
                    .opacity(0.6)

                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(cardBorder, lineWidth: 0.8)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: 2)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateTitle(summary.date, calendar: calendar, locale: locale))
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()
            
            // Show mood emoji before chevron
            if let emoji = summary.moodEmoji {
                Text(emoji)
                    .font(.title2)
            }

            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(.spring(response: 0.28, dampingFraction: 0.9), value: isExpanded)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Journal entry (mood + text)
            if let journalText = summary.journalText {
                HStack(alignment: .top, spacing: 12) {
                    icon("book.fill", tint: .purple)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Journal")
                            .font(.subheadline).bold()
                        Text(journalText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            
            if let workDuration = summary.workDurationMinutes, workDuration > 0 {
                HStack(alignment: .center, spacing: 12) {
                    icon("briefcase.fill", tint: .blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Work")
                            .font(.subheadline).bold()
                        let hours = workDuration / 60
                        let minutes = workDuration % 60
                        let durationText = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
                        let objectText = summary.workObject != nil ? " (\(summary.workObject!))" : ""
                        Text("Worked \(durationText)\(objectText)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            
            if let calories = summary.totalCalories, calories != 0 {
                HStack(alignment: .center, spacing: 12) {
                    icon("flame.fill", tint: .orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Calories")
                            .font(.subheadline).bold()
                        Text("\(calories.clean(maxDecimals: 1)) kcal")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            
            if let balance = summary.balance, balance != 0 {
                HStack(alignment: .center, spacing: 12) {
                    icon("dollarsign.circle.fill", tint: balance >= 0 ? .green : .red)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Net Change")
                            .font(.subheadline).bold()
                        let sign = balance >= 0 ? "+" : ""
                        let balanceStr = balance.clean(maxDecimals: 2)
                        let balanceText = "\(sign)\(balanceStr) \(summary.baseCurrency)"
                        
                        Text(balanceText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            Divider()
                .padding(.vertical, 4)
            
            Button {
                onManageEntries(summary.date)
            } label: {
                HStack {
                    Image(systemName: "list.bullet.indent")
                    Text("Manage Entries")
                }
                .font(.footnote.bold())
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func icon(_ systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.palette)
            .foregroundStyle(tint, tint.opacity(0.25))
            .frame(width: 22, height: 22)
    }

    private func dateTitle(_ date: Date, calendar: Calendar, locale: Locale) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }

        let df = DateFormatter()
        df.locale = locale
        df.calendar = calendar
        df.dateFormat = "EEE, d MMM"
        DateHelper.applyDateFormat(df)
        return df.string(from: date)
    }

    private var headerSubtitle: String {
        var parts: [String] = []
        if let workDuration = summary.workDurationMinutes, workDuration > 0 {
            let hours = workDuration / 60
            let minutes = workDuration % 60
            let durationText = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
            parts.append("Worked \(durationText)")
        }
        if let calories = summary.totalCalories, calories != 0 {
            let sign = calories >= 0 ? "+" : ""
            let calStr = calories.clean(maxDecimals: 1)
            parts.append("\(sign)\(calStr) kcal")
        }
        if let balance = summary.balance, balance != 0 {
            let sign = balance >= 0 ? "+" : ""
            let balanceStr = balance.clean(maxDecimals: 2)
            parts.append("\(sign)\(balanceStr) \(summary.baseCurrency)")
        }
        if parts.isEmpty { return "No activity" }
        return parts.joined(separator: " • ")
    }

    private var cardBackground: some ShapeStyle {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.2) : .black.opacity(0.08)
    }
}
