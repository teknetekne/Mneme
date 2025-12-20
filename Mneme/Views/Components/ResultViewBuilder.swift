import SwiftUI
import UIKit

struct ResultViewBuilder: View {
    let results: [ParsingResultItem]
    let status: ParseStatus
    let parseSources: (String?) -> [CalorieSource]
    let faviconURL: (String) -> URL?
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        if status == .loading && results.isEmpty {
            RotatingIcon(iconName: "arrow.2.circlepath")
                .font(.callout)
                .frame(width: 20, alignment: .leading)
        } else if let intentItem = results.first(where: { $0.field == "Intent" }) {
            let normalizedIntent = NotepadFormatter.normalizeIntentForCheck(intentItem.value)
            buildIntentView(intent: normalizedIntent)
        } else {
            buildStatusIcon()
        }
    }
    
    @ViewBuilder
    private func buildIntentView(intent: String) -> some View {
        let isWorkIntent = intent == "work_start" || intent == "work_end" || 
                          intent.contains("work_start") || intent.contains("work_end")
        let isMealIntent = intent == "meal"
        let isIncomeExpenseIntent = intent == "income" || intent == "expense"
        let isActivityIntent = intent == "activity"
        
        if isWorkIntent, let timeItem = results.first(where: { ($0.field == "Event Time" || $0.field == "Reminder Time") && $0.isValid }) {
            buildTimeView(timeItem: timeItem)
        } else if isMealIntent, results.first(where: { $0.field == "Calories" && $0.isValid }) != nil {
            MealCaloriesView(
                status: status,
                results: results,
                parseSources: parseSources,
                faviconURL: faviconURL
            )
        } else if isIncomeExpenseIntent, let amountItem = results.first(where: { $0.field == "Amount" && $0.isValid }) {
            buildAmountView(amountItem: amountItem)
        } else if isActivityIntent, let caloriesItem = results.first(where: { $0.field == "Calories Burned" && $0.isValid }) {
            buildActivityView(caloriesItem: caloriesItem)
        } else {
            buildStatusIcon()
        }
    }
    
    @ViewBuilder
    private func buildTimeView(timeItem: ParsingResultItem) -> some View {
        Group {
            if status == .loading {
                RotatingIcon(iconName: "arrow.2.circlepath")
            } else {
                Text(timeItem.value)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
    
    @ViewBuilder
    private func buildAmountView(amountItem: ParsingResultItem) -> some View {
        Group {
            if status == .loading {
                RotatingIcon(iconName: "arrow.2.circlepath")
            } else {
                Text(amountItem.value)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
    
    @ViewBuilder
    private func buildActivityView(caloriesItem: ParsingResultItem) -> some View {
        Group {
            if status == .loading {
                RotatingIcon(iconName: "arrow.2.circlepath")
            } else {
                Text(caloriesItem.value)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
    
    @ViewBuilder
    private func buildStatusIcon() -> some View {
        Group {
            switch status {
            case .idle: EmptyView()
            case .loading: RotatingIcon(iconName: "arrow.2.circlepath")
            case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .error:
                if let errorItem = results.first(where: { !$0.isValid && $0.errorMessage != nil }),
                   let errorMessage = errorItem.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                } else {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                }
            }
        }
        .font(.callout)
        .frame(alignment: .leading) // Removed fixed width 20 constraint for text
    }
}

struct MealCaloriesView: View {
    @Environment(\.colorScheme) private var colorScheme
    let status: ParseStatus
    let results: [ParsingResultItem]
    let parseSources: (String?) -> [CalorieSource]
    let faviconURL: (String) -> URL?
    
    var body: some View {
        Group {
            if status == .loading {
                RotatingIcon(iconName: "arrow.2.circlepath")
            } else {
                let individualMealCalories = results.filter { $0.field.hasPrefix("Calories - ") && $0.isValid }
                let totalCaloriesItem = results.first(where: { $0.field == "Calories" && $0.isValid })
                
                if !individualMealCalories.isEmpty, let totalItem = totalCaloriesItem {
                    buildMultiMealView(totalItem: totalItem, individualMealCalories: individualMealCalories)
                } else if let caloriesItem = totalCaloriesItem {
                    buildSingleMealView(caloriesItem: caloriesItem)
                }
            }
        }
    }
    
    @ViewBuilder
    private func buildMultiMealView(totalItem: ParsingResultItem, individualMealCalories: [ParsingResultItem]) -> some View {
        Text(totalItem.value)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    
    @ViewBuilder
    private func buildSingleMealView(caloriesItem: ParsingResultItem) -> some View {
        Text(caloriesItem.value)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

private struct RotatingIcon: View {
    let iconName: String
    @State private var rotation: Double = 0
    
    var body: some View {
        Image(systemName: iconName)
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}

