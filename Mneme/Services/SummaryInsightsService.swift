import Foundation
import FoundationModels

struct SummaryInsightResult {
    let overview: String
    let highlights: [String]
    let usedModel: Bool
}

private struct DailyInsightDatum {
    let date: Date
    let moodEmoji: String?
    let moodScore: Int?
    let workMinutes: Int?
    let caloriesConsumed: Double?
    let caloriesBurned: Double?
    let netCalories: Double?
    let totalIncome: Double?
    let totalExpense: Double?
    let netBalance: Double?
}

@Generable(description: "Simple, natural insights about daily patterns")
private struct SummaryInsightsLLMResponse {
    @Guide(description: "A simple, natural English overview (30-50 words) about what you notice. Write casually, like you're making an observation. No jargon or technical terms.")
    let overview: String
    
    @Guide(description: "Up to 4 simple English bullets about interesting patterns. Write naturally and directly. Include numbers when relevant (e.g., '5 out of 7 days'). Keep it straightforward and personal.")
    let bullets: [String]
}

final class SummaryInsightsService {
    static let shared = SummaryInsightsService()
    
    private let model: SystemLanguageModel
    private let instructions: Instructions
    
    private init() {
        self.model = SystemLanguageModel.default
        self.instructions = Instructions(
            """
            Look at someone's daily data: date, mood (emoji and score -2 to 2), work minutes, calories (consumed, burned, net), total income, total expense, net balance.
            
            Find simple, interesting patterns and CORRELATIONS. Write naturally, like you're noticing something about their life.
            
            Rules:
            - Need at least 3 data points to mention something.
            - Include numbers when relevant (e.g., "5 out of 8 days").
            - Write in simple, natural English.
            - No jargon, statistics terms, or generic advice.
            - STRENGTH: Look for connections (e.g., "You tend to earn more on days you work longer", "Your mood is better on days you spend less").
            """
        )
    }
    
    func analyze(
        days: Int = 30,
        workSessionStore: WorkSessionStore,
        notepadEntryStore: NotepadEntryStore,
        currencySettingsStore: CurrencySettingsStore,
        healthKitService: HealthKitService
    ) async -> SummaryInsightResult {
        let metrics = await collectMetrics(
            days: days,
            workSessionStore: workSessionStore,
            notepadEntryStore: notepadEntryStore,
            currencySettingsStore: currencySettingsStore,
            healthKitService: healthKitService
        )
        
        guard !metrics.isEmpty else {
            return SummaryInsightResult(
                overview: "Not enough daily data to find patterns yet. Keep tracking and check back soon!",
                highlights: [],
                usedModel: false
            )
        }
        
        if model.availability == .available, let llmResult = await generateWithLLM(from: metrics) {
            return llmResult
        }
        
        return fallbackInsights(from: metrics)
    }
    
    private func collectMetrics(
        days: Int,
        workSessionStore: WorkSessionStore,
        notepadEntryStore: NotepadEntryStore,
        currencySettingsStore: CurrencySettingsStore,
        healthKitService: HealthKitService
    ) async -> [DailyInsightDatum] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var metrics: [DailyInsightDatum] = []
        
        for offset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            if let datum = await buildDatum(
                for: date,
                workSessionStore: workSessionStore,
                notepadEntryStore: notepadEntryStore,
                currencySettingsStore: currencySettingsStore,
                healthKitService: healthKitService
            ) {
                metrics.append(datum)
            }
        }
        
        return metrics.sorted { $0.date > $1.date }
    }
    
    private func buildDatum(
        for date: Date,
        workSessionStore: WorkSessionStore,
        notepadEntryStore: NotepadEntryStore,
        currencySettingsStore: CurrencySettingsStore,
        healthKitService: HealthKitService
    ) async -> DailyInsightDatum? {
        let calendar = Calendar.current
        let dayEntries = await MainActor.run { notepadEntryStore.getEntries(for: date) }
        let baseCurrency = await MainActor.run { currencySettingsStore.baseCurrency }
        
        // Mood
        let mood = extractMood(from: dayEntries)
        
        // Work
        let workData = await MainActor.run { workSessionStore.getTotalWorkDuration(for: date) }
        let workMinutes = workData?.minutes
        
        // Calories (meals + adjustments + active energy)
        var consumed: Double = 0.0
        var burned: Double = 0.0
        var hasCalorieData = false
        
        for entry in dayEntries {
            if let kcal = entry.mealKcal {
                consumed += kcal
                hasCalorieData = true
            }
        }
        
        if healthKitService.isAuthorized, let activeEnergy = await healthKitService.getActiveEnergyBurned(for: date) {
            burned = activeEnergy
            hasCalorieData = true
        }
        
        let resolvedConsumed = hasCalorieData ? consumed : nil
        let resolvedBurned = hasCalorieData ? burned : nil
        let resolvedNetCalories = hasCalorieData ? (consumed - burned) : nil
        
        // Financials in base currency
        var totalIncome: Double = 0.0
        var totalExpense: Double = 0.0
        var hasBalanceData = false
        
        for entry in dayEntries {
            guard let intent = entry.intent,
                  (intent == "income" || intent == "expense"),
                  let amount = entry.amount,
                  let currency = entry.currency else { continue }
            
            hasBalanceData = true
            
            let convertedAmount: Double
            if let converted = await CurrencyService.shared.convertAmount(abs(amount), from: currency, to: baseCurrency) {
                convertedAmount = converted
            } else {
                convertedAmount = abs(amount)
            }
            
            if intent == "income" {
                totalIncome += convertedAmount
            } else {
                totalExpense += convertedAmount
            }
        }
        
        let resolvedIncome = hasBalanceData ? totalIncome : nil
        let resolvedExpense = hasBalanceData ? totalExpense : nil
        let resolvedBalance = hasBalanceData ? (totalIncome - totalExpense) : nil
        
        if mood == nil && workMinutes == nil && resolvedNetCalories == nil && resolvedBalance == nil {
            return nil
        }
        
        return DailyInsightDatum(
            date: calendar.startOfDay(for: date),
            moodEmoji: mood?.emoji,
            moodScore: mood?.score,
            workMinutes: workMinutes,
            caloriesConsumed: resolvedConsumed,
            caloriesBurned: resolvedBurned,
            netCalories: resolvedNetCalories,
            totalIncome: resolvedIncome,
            totalExpense: resolvedExpense,
            netBalance: resolvedBalance
        )
    }
    
    private func extractMood(from entries: [ParsedNotepadEntry]) -> (emoji: String, score: Int)? {
        let moodEmojis: [String: Int] = [
            "😢": -2,
            "😕": -1,
            "😐": 0,
            "🙂": 1,
            "😊": 2
        ]
        
        for entry in entries {
            if entry.intent == "journal" {
                for (emoji, score) in moodEmojis {
                    if entry.originalText.hasPrefix(emoji) {
                        return (emoji, score)
                    }
                }
            }
        }
        
        return nil
    }
    
    private func generateWithLLM(from metrics: [DailyInsightDatum]) async -> SummaryInsightResult? {
        let rows = formatDataset(metrics)
        let promptText = """
        Daily data (\(metrics.count) days, newest to oldest):
        date | mood_score | mood_emoji | work_min | cal_consumed | cal_burned | cal_net | income | expense | net_balance
        \(rows)
        
        What patterns or correlations do you notice? Write simply and naturally about what stands out. 
        Examples of what to look for:
        - "You were often sad on days you earned a lot of money."
        - "You worked much more on days your mood was high."
        - "Expenses were higher on days you worked less."
        """
        
        do {
            let session = LanguageModelSession(instructions: instructions)
            let prompt = Prompt(promptText)
            let response = try await session.respond(
                generating: SummaryInsightsLLMResponse.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(),
                prompt: { prompt }
            )
            
            let bullets = response.content.bullets.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            
            if bullets.isEmpty {
                return fallbackInsights(from: metrics)
            }
            
            return SummaryInsightResult(
                overview: response.content.overview.trimmingCharacters(in: .whitespacesAndNewlines),
                highlights: bullets,
                usedModel: true
            )
        } catch {
            return nil
        }
    }
    
    private func fallbackInsights(from metrics: [DailyInsightDatum]) -> SummaryInsightResult {
        let moodMetrics = metrics.compactMap { datum -> (score: Int, work: Int?, calories: Double?, balance: Double?)? in
            guard let score = datum.moodScore else { return nil }
            return (score, datum.workMinutes, datum.netCalories, datum.netBalance)
        }
        
        var highlights: [String] = []
        
        // Mood vs Work
        let highMoodWork = moodMetrics.filter { $0.score >= 1 }.compactMap { $0.work }
        let lowMoodWork = moodMetrics.filter { $0.score <= -1 }.compactMap { $0.work }
        if let highAvg = average(highMoodWork), let lowAvg = average(lowMoodWork), abs(highAvg - lowAvg) >= 30, highMoodWork.count >= 3, lowMoodWork.count >= 3 {
            if highAvg > lowAvg {
                highlights.append("On \(highMoodWork.count) happier days, you worked \(Int(highAvg - lowAvg)) minutes longer (\(Int(highAvg)) vs \(Int(lowAvg)) min).")
            } else {
                highlights.append("On \(highMoodWork.count) happier days, you worked \(Int(lowAvg - highAvg)) minutes less (\(Int(highAvg)) vs \(Int(lowAvg)) min).")
            }
        }
        
        // Mood vs Calories
        let highMoodCalories = moodMetrics.filter { $0.score >= 1 }.compactMap { $0.calories }
        let lowMoodCalories = moodMetrics.filter { $0.score <= -1 }.compactMap { $0.calories }
        if let highAvg = average(highMoodCalories), let lowAvg = average(lowMoodCalories), abs(highAvg - lowAvg) >= 150, highMoodCalories.count >= 3, lowMoodCalories.count >= 3 {
            if highAvg < lowAvg {
                highlights.append("On \(highMoodCalories.count) happier days, net calories were \(Int(lowAvg - highAvg)) lower (\(Int(highAvg)) vs \(Int(lowAvg))).")
            } else {
                highlights.append("On \(highMoodCalories.count) happier days, net calories were \(Int(highAvg - lowAvg)) higher (\(Int(highAvg)) vs \(Int(lowAvg))).")
            }
        }
        
        // Mood vs Balance
        let highMoodBalance = moodMetrics.filter { $0.score >= 1 }.compactMap { $0.balance }
        let lowMoodBalance = moodMetrics.filter { $0.score <= -1 }.compactMap { $0.balance }
        if let highAvg = average(highMoodBalance), let lowAvg = average(lowMoodBalance), abs(highAvg - lowAvg) >= 10, highMoodBalance.count >= 3, lowMoodBalance.count >= 3 {
            if highAvg > lowAvg {
                highlights.append("On \(highMoodBalance.count) happier days, balance was \((highAvg - lowAvg).clean(maxDecimals: 0)) more positive (\(highAvg.clean(maxDecimals: 0)) vs \(lowAvg.clean(maxDecimals: 0))).")
            } else {
                highlights.append("On \(highMoodBalance.count) happier days, balance was \(abs(highAvg - lowAvg).clean(maxDecimals: 0)) less (\(highAvg.clean(maxDecimals: 0)) vs \(lowAvg.clean(maxDecimals: 0))).")
            }
        }
        
        // Work vs Balance
        let workMetrics = metrics.compactMap { datum -> (work: Int, balance: Double?)? in
            guard let work = datum.workMinutes else { return nil }
            return (work, datum.netBalance)
        }
        let highWorkBalance = workMetrics.filter { $0.work >= 480 }.compactMap { $0.balance } // 8+ hours
        let lowWorkBalance = workMetrics.filter { $0.work < 240 }.compactMap { $0.balance } // < 4 hours
        if let highAvg = average(highWorkBalance), let lowAvg = average(lowWorkBalance), abs(highAvg - lowAvg) >= 20, highWorkBalance.count >= 3, lowWorkBalance.count >= 3 {
            if highAvg > lowAvg {
                highlights.append("On days you worked 8+ hours, you earned about \((highAvg - lowAvg).clean(maxDecimals: 0)) more than on lighter days (\(highAvg.clean(maxDecimals: 0)) vs \(lowAvg.clean(maxDecimals: 0))).")
            }
        }
        
        if highlights.count > 4 {
            highlights = Array(highlights.prefix(4))
        }
        
        if highlights.isEmpty {
            highlights.append("Add more mood entries to see patterns.")
        }
        
        let moodDays = moodMetrics.count
        let overview = "Last \(metrics.count) days, \(moodDays) with mood entries."
        
        return SummaryInsightResult(
            overview: overview,
            highlights: highlights,
            usedModel: false
        )
    }
    
    private func average(_ values: [Int]) -> Double? {
        guard !values.isEmpty else { return nil }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
    
    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
    
    private func formatDataset(_ metrics: [DailyInsightDatum]) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMMM d"
        df.locale = Locale(identifier: "en_US")
        
        return metrics.map { datum in
            let dateString = df.string(from: datum.date)
            let moodScore = datum.moodScore.map { String($0) } ?? "nil"
            let moodEmoji = datum.moodEmoji ?? "nil"
            let work = datum.workMinutes.map { "\($0)" } ?? "nil"
            let consumed = datum.caloriesConsumed.map { $0.clean(maxDecimals: 0) } ?? "nil"
            let burned = datum.caloriesBurned.map { $0.clean(maxDecimals: 0) } ?? "nil"
            let netCals = datum.netCalories.map { $0.clean(maxDecimals: 0) } ?? "nil"
            let totalIncome = datum.totalIncome.map { $0.clean(maxDecimals: 2) } ?? "nil"
            let totalExpense = datum.totalExpense.map { $0.clean(maxDecimals: 2) } ?? "nil"
            let balance = datum.netBalance.map { $0.clean(maxDecimals: 2) } ?? "nil"
            
            return "\(dateString) | \(moodScore) | \(moodEmoji) | \(work) | \(consumed) | \(burned) | \(netCals) | \(totalIncome) | \(totalExpense) | \(balance)"
        }
        .joined(separator: "\n")
    }
}

