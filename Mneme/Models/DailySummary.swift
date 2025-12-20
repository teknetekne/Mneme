import Foundation

/// Model for daily summary data used in Overview and Daily History
struct DailySummary: Identifiable {
    var id: Date { date }
    let date: Date
    let remindersCompleted: Int
    let eventsCount: Int
    let moodEmoji: String?
    let journalText: String?
    let workDurationMinutes: Int?
    let workObject: String?
    let totalCalories: Double?
    let balance: Double?
    let balanceByCurrency: [String: Double]?
    let baseCurrency: String
}
