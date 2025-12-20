import Foundation
import FoundationModels

// MARK: - Activity Parser Service

actor ActivityParserService {
    static let shared = ActivityParserService()
    
    private let model: SystemLanguageModel
    private let instructions: Instructions
    private var cache: [String: ActivityParsedResult] = [:]
    
    private init() {
        self.model = SystemLanguageModel.default
        self.instructions = Instructions("""
        Parse activity information from user input in ANY language. Extract activity type, duration, distance, and count (repetitions).
        
        CRITICAL RULES:
        - activityType: The type of activity. Must be in English lowercase. Examples: "run", "walk", "swim", "pushups", "situps" (NOT "mekik"), "squats", "burpees".
        - duration: ONLY if user explicitly mentions time (e.g., "30 minutes", "1 hour"). Return nil otherwise. DO NOT GUESS OR CALCULATE.
        - distance: Distance in kilometers. Convert miles to km if needed. Return nil if not mentioned.
        - count: Number of repetitions for exercises (e.g., "100 pushups" -> 100, "50 mekik" -> 50, "30 şınav" -> 30). Return nil if not mentioned.
        - calories_burned: ALWAYS set to 0.
        
        EXAMPLES:
        - "10 km koştum" -> activityType: "run", duration: nil, distance: 10.0, count: nil
        - "30 dakika koştum" -> activityType: "run", duration: 30.0, distance: nil, count: nil
        - "100 şınav" -> activityType: "pushups", duration: nil, distance: nil, count: 100.0
        - "50 mekik" -> activityType: "situps", duration: nil, distance: nil, count: 50.0
        """)
    }
    
    // MARK: - Public Methods
    
    func parseActivity(from text: String) async -> ActivityParsedResult? {
        // Check cache first
        if let cached = cache[text] {
            return cached
        }
        
        guard model.availability == .available else { return nil }
        
        do {
            let prompt = Prompt(text)
            let session = LanguageModelSession(instructions: instructions)
            
            let response = try await session.respond(
                generating: ActivityParsedEntry.self,
                includeSchemaInPrompt: true,
                options: GenerationOptions(),
                prompt: { prompt }
            )
            
            var entry = response.content
            
            // SMART VALIDATION: Override suspicious duration values
            // If we have distance but duration seems wrong (e.g., LLM hallucinating 60 mins for 1km)
            if let distance = entry.distance, distance > 0 {
                let estimatedDuration = estimateDuration(for: entry.activity_type, distance: distance)
                
                // If duration is nil, missing, or suspiciously close to a round number (LLM artifact)
                // AND differs significantly from our estimate, use the estimate instead
                if let currentDuration = entry.duration {
                    let ratio = currentDuration / estimatedDuration
                    // If LLM duration is wildly off (>2x or <0.5x our estimate), override it
                    if ratio > 2.0 || ratio < 0.5 {
                        // Only log if this is a new parse (not from cache)
                        // Since we're in parseActivity and not checking cache yet, this is fine
                        // But we'll reduce verbosity - only log significant overrides
                        entry.duration = estimatedDuration
                    }
                } else {
                    entry.duration = estimatedDuration
                }
            }
            
            // If no distance but we have count, estimate duration from repetitions
            if entry.duration == nil, let count = entry.count {
                entry.duration = estimateDurationFromCount(for: entry.activity_type, count: count)
            }
            
            // Calculate calories
            var calories: Double = 0
            var processingError: Error?
            
            do {
                calories = try await calculateCalories(for: entry)
            } catch {
                processingError = error
            }
            
            let result = ActivityParsedResult(
                activityType: entry.activity_type,
                duration: entry.duration,
                distance: entry.distance,
                caloriesBurned: calories,
                errorMessage: processingError?.localizedDescription
            )
            
            // Cache the result
            cache[text] = result
            
            return result
        } catch {
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    private func calculateCalories(for entry: ActivityParsedEntry) async throws -> Double {
        // ... (existing implementation)
        let calorieService = await MainActor.run { ActivityCalorieService.shared }
        
        // If we have explicit duration, use it
        if let duration = entry.duration, duration > 0 {
            return try await calorieService.calculateCalories(
                for: entry.activity_type,
                duration: duration,
                distance: entry.distance
            )
        }
        
        // If no duration, try to estimate it from distance or count
        var estimatedDuration: Double = 0
        
        if let distance = entry.distance, distance > 0 {
            estimatedDuration = estimateDuration(for: entry.activity_type, distance: distance)
        } else if let count = entry.count, count > 0 {
            estimatedDuration = estimateDurationFromCount(for: entry.activity_type, count: count)
        }
        
        if estimatedDuration > 0 {
            return try await calorieService.calculateCalories(
                for: entry.activity_type,
                duration: estimatedDuration,
                distance: entry.distance
            )
        }
        
        return 0
    }
    
    private func estimateDuration(for activityType: String, distance: Double) -> Double {
        let activityLower = activityType.lowercased()
        
        let averageSpeed: Double // km/h
        
        if activityLower.contains("run") || activityLower.contains("koş") || activityLower.contains("jog") {
            averageSpeed = 10.0
        } else if activityLower.contains("walk") || activityLower.contains("yürü") || activityLower.contains("hik") {
            averageSpeed = 5.0
        } else if activityLower.contains("cycl") || activityLower.contains("bisiklet") || activityLower.contains("bik") {
            averageSpeed = 20.0
        } else if activityLower.contains("swim") || activityLower.contains("yüz") {
            averageSpeed = 3.0
        } else if activityLower.contains("row") || activityLower.contains("kürek") {
            averageSpeed = 8.0 // Rowing machine or water
        } else if activityLower.contains("ski") || activityLower.contains("kayak") {
            averageSpeed = 9.0 // Cross-country skiing estimate
        } else if activityLower.contains("skat") || activityLower.contains("paten") {
            averageSpeed = 12.0 // Rollerblading/Ice skating
        } else {
            averageSpeed = 5.0 // Default fallback (walking speed)
        }
        
        let durationInHours = distance / averageSpeed
        let durationInMinutes = durationInHours * 60
        
        return durationInMinutes
    }
    
    private func estimateDurationFromCount(for activityType: String, count: Double) -> Double {
        let activityLower = activityType.lowercased()
        
        // Seconds per repetition
        let secondsPerRep: Double
        
        if activityLower.contains("pushup") || activityLower.contains("push-up") || activityLower.contains("şınav") {
            secondsPerRep = 3.0
        } else if activityLower.contains("situp") || activityLower.contains("sit-up") || activityLower.contains("mekik") {
            secondsPerRep = 3.0
        } else if activityLower.contains("squat") || activityLower.contains("çömelme") {
            secondsPerRep = 3.0
        } else if activityLower.contains("burpee") {
            secondsPerRep = 5.0
        } else if activityLower.contains("pullup") || activityLower.contains("pull-up") || activityLower.contains("barfiks") {
            secondsPerRep = 4.0
        } else if activityLower.contains("jump") || activityLower.contains("zıpla") || activityLower.contains("jack") {
            secondsPerRep = 1.5 // Jumping jacks
        } else if activityLower.contains("lunge") {
            secondsPerRep = 3.0
        } else {
            secondsPerRep = 3.0 // Default
        }
        
        let totalSeconds = count * secondsPerRep
        let durationInMinutes = totalSeconds / 60.0
        
        return durationInMinutes
    }
}

// MARK: - Activity Parsed Entry

@Generable(description: "Physical activity information extracted from user text")
struct ActivityParsedEntry {
    @Guide(description: "The type of physical activity (e.g., running, walking, cycling, swimming, gym, yoga, pushups). Must be in lowercase English.")
    var activity_type: String
    
    @Guide(description: "Duration of the activity in MINUTES. Convert hours to minutes (1 hour = 60 minutes). Null if not mentioned.")
    var duration: Double?
    
    @Guide(description: "Distance covered in KILOMETERS. Convert miles to km (1 mile = 1.6 km). Null if not mentioned.")
    var distance: Double?
    
    @Guide(description: "Number of repetitions or sets (e.g., 100 pushups, 3 sets). Null if not mentioned.")
    var count: Double?
    
    @Guide(description: "Calories burned during the activity. ALWAYS set to 0, will be calculated automatically.")
    var calories_burned: Double
}

// MARK: - Activity Parsed Result

struct ActivityParsedResult: Sendable {
    let activityType: String
    let duration: Double?      // minutes
    let distance: Double?      // km
    let caloriesBurned: Double // kcal
    let errorMessage: String?
    
    nonisolated init(activityType: String, duration: Double?, distance: Double?, caloriesBurned: Double, errorMessage: String? = nil) {
        self.activityType = activityType
        self.duration = duration
        self.distance = distance
        self.caloriesBurned = caloriesBurned
        self.errorMessage = errorMessage
    }
    
    var formattedDuration: String? {
        guard let duration = duration else { return nil }
        if duration >= 60 {
            let hours = Int(duration / 60)
            let minutes = Int(duration.truncatingRemainder(dividingBy: 60))
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(hours)h"
            }
        } else {
            return "\(Int(duration))m"
        }
    }
    
    var formattedDistance: String? {
        guard let distance = distance else { return nil }
        return String(format: "%.1f km", distance)
    }
    
    var formattedCalories: String {
        let rounded = Int(caloriesBurned.rounded())
        guard rounded > 0 else { return "0 kcal" }
        return "-\(rounded) kcal"
    }
}
