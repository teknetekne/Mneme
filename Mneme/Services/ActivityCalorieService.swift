import Foundation
import HealthKit

// MARK: - Activity Calorie Service

enum ActivityCalorieError: LocalizedError {
    case missingHealthMetrics
    
    var errorDescription: String? {
        switch self {
        case .missingHealthMetrics:
            return "Missing height/weight data for calorie calculation"
        }
    }
}

final class ActivityCalorieService {
    static let shared = ActivityCalorieService()
    
    private let healthStore = HKHealthStore()
    
    private init() {}
    
    // MARK: - Public Methods
    
    func calculateCalories(for activity: String, duration: Double, distance: Double? = nil) async throws -> Double {
        guard let userProfile = await getUserProfile() else {
            throw ActivityCalorieError.missingHealthMetrics
        }
        
        return calculateCaloriesWithProfile(profile: userProfile, activity: activity, duration: duration, distance: distance)
    }
    
    private func calculateCaloriesWithProfile(profile: ActivityUserProfile, activity: String, duration: Double, distance: Double?) -> Double {
        let met = getMETValue(for: activity, distance: distance, duration: duration)
        let durationInHours = duration / 60.0
        let calories = met * profile.weight * durationInHours
        return calories
    }
    
    private func getMETValue(for activity: String, distance: Double?, duration: Double) -> Double {
        let activityLower = activity.lowercased()
        
        if let distance = distance, duration > 0 {
            let speed = (distance / duration) * 60.0
            
            if activityLower.contains("run") || activityLower.contains("koş") || activityLower.contains("jog") {
                return getMETForRunning(speed: speed)
            } else if activityLower.contains("cycl") || activityLower.contains("bisiklet") || activityLower.contains("bike") {
                return getMETForCycling(speed: speed)
            } else if activityLower.contains("walk") || activityLower.contains("yürü") {
                return getMETForWalking(speed: speed)
            }
        }
        
        return ActivityMETValues.getMET(for: activityLower)
    }
    
    private func getMETForRunning(speed: Double) -> Double {
        switch speed {
        case 0..<6.4: return 6.0
        case 6.4..<8.0: return 8.3
        case 8.0..<8.4: return 9.0
        case 8.4..<9.7: return 9.8
        case 9.7..<10.8: return 10.5
        case 10.8..<11.3: return 11.0
        case 11.3..<12.1: return 11.5
        case 12.1..<12.9: return 11.8
        case 12.9..<13.8: return 12.3
        case 13.8..<14.5: return 12.8
        case 14.5...: return 14.5
        default: return 9.8
        }
    }
    
    private func getMETForCycling(speed: Double) -> Double {
        switch speed {
        case 0..<16: return 4.0
        case 16..<19: return 6.8
        case 19..<22: return 8.0
        case 22..<26: return 10.0
        case 26..<32: return 12.0
        case 32...: return 15.8
        default: return 8.0
        }
    }
    
    private func getMETForWalking(speed: Double) -> Double {
        switch speed {
        case 0..<3.2: return 2.0
        case 3.2..<4.0: return 2.8
        case 4.0..<4.8: return 3.5
        case 4.8..<5.6: return 4.3
        case 5.6..<6.4: return 5.0
        case 6.4...: return 7.0
        default: return 3.5
        }
    }
    
    private func getUserProfile() async -> ActivityUserProfile? {
        // Try HealthKit first if available
        if HKHealthStore.isHealthDataAvailable() {
            let readTypes: Set<HKObjectType> = [
                HKObjectType.quantityType(forIdentifier: .bodyMass)!,
                HKObjectType.quantityType(forIdentifier: .height)!,
                HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!,
                HKObjectType.characteristicType(forIdentifier: .biologicalSex)!
            ]
            
            let status = healthStore.authorizationStatus(for: HKObjectType.quantityType(forIdentifier: .bodyMass)!)
            if status == .notDetermined {
                do {
                    try await healthStore.requestAuthorization(toShare: [], read: readTypes)
                } catch {
                    // Continue to fallback
                }
            }
            
            do {
                let weight = try await getLatestWeight()
                let height = try await getLatestHeight()
                let age = try await getAge()
                let biologicalSex = try await getBiologicalSex()
                
                return ActivityUserProfile(weight: weight, height: height, age: age, biologicalSex: biologicalSex)
            } catch {
                // Fallthrough to fallback
            }
        }
        
        // Fallback to UserSettingsStore
        return await getStoredProfile()
    }
    
    private func getStoredProfile() async -> ActivityUserProfile? {
        await MainActor.run {
            let store = UserSettingsStore.shared
            
            guard let weight = store.weight,
                  let height = store.height else {
                return nil
            }
            
            let age = store.age ?? 30
            let biologicalSex: HKBiologicalSex
            
            switch store.biologicalSex {
            case .male: biologicalSex = .male
            case .female: biologicalSex = .female
            case .other: biologicalSex = .other
            case .notSet: biologicalSex = .notSet
            }
            
            return ActivityUserProfile(weight: weight, height: height, age: age, biologicalSex: biologicalSex)
        }
    }
    
    private func getLatestWeight() async throws -> Double {
        let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        return try await withCheckedThrowingContinuation { continuation in
            let queryWithContinuation = HKSampleQuery(sampleType: weightType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let sample = results?.first as? HKQuantitySample else {
                    continuation.resume(throwing: ActivityCalorieError.missingHealthMetrics)
                    return
                }
                
                let weight = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
                continuation.resume(returning: weight)
            }
            
            healthStore.execute(queryWithContinuation)
        }
    }
    
    private func getLatestHeight() async throws -> Double {
        let heightType = HKQuantityType.quantityType(forIdentifier: .height)!
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: heightType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let sample = results?.first as? HKQuantitySample else {
                    continuation.resume(throwing: ActivityCalorieError.missingHealthMetrics)
                    return
                }
                
                let height = sample.quantity.doubleValue(for: HKUnit.meterUnit(with: .centi))
                continuation.resume(returning: height)
            }
            
            healthStore.execute(query)
        }
    }
    
    private func getAge() async throws -> Int {
        do {
            let birthdayComponents = try healthStore.dateOfBirthComponents()
            let calendar = Calendar.current
            let now = Date()
            let age = calendar.dateComponents([.year], from: birthdayComponents.date!, to: now).year ?? 30
            return age
        } catch {
            return 30
        }
    }
    
    private func getBiologicalSex() async throws -> HKBiologicalSex {
        do {
            let biologicalSexObject = try healthStore.biologicalSex()
            return biologicalSexObject.biologicalSex
        } catch {
            return .male
        }
    }
}

// MARK: - User Profile

struct ActivityUserProfile {
    let weight: Double     // kg
    let height: Double     // cm
    let age: Int          // years
    let biologicalSex: HKBiologicalSex
    
    var bmr: Double {
        let sexFactor: Double = biologicalSex == .male ? 5 : -161
        return (10 * weight) + (6.25 * height) - (5 * Double(age)) + sexFactor
    }
}

// MARK: - Activity MET Values

struct ActivityMETValues {
    private static let metValues: [String: Double] = [
        "running": 9.8,
        "jogging": 7.0,
        "run": 9.8,
        "koşu": 9.8,
        "koş": 9.8,
        "sprint": 12.3,
        
        "walking": 3.5,
        "walk": 3.5,
        "yürüyüş": 3.5,
        "yürü": 3.5,
        "hiking": 6.0,
        "trekking": 6.5,
        
        "cycling": 8.0,
        "bike": 8.0,
        "bisiklet": 8.0,
        "mountain biking": 8.5,
        "stationary bike": 6.8,
        
        "swimming": 8.0,
        "swim": 8.0,
        "yüzme": 8.0,
        "freestyle": 9.8,
        "breaststroke": 10.3,
        "backstroke": 7.0,
        "butterfly": 13.8,
        
        "football": 8.0,
        "futbol": 8.0,
        "soccer": 10.0,
        "basketball": 6.5,
        "basketbol": 6.5,
        "volleyball": 4.0,
        "voleybol": 4.0,
        "tennis": 7.3,
        "tenis": 7.3,
        "badminton": 5.5,
        "table tennis": 4.0,
        "masa tenisi": 4.0,
        
        "weight training": 6.0,
        "ağırlık": 6.0,
        "gym": 6.0,
        "aerobics": 7.3,
        "aerobik": 7.3,
        "zumba": 8.8,
        "crossfit": 8.0,
        "circuit training": 8.0,
        "hiit": 12.3,
        "tabata": 12.3,
        
        "yoga": 2.5,
        "hatha yoga": 2.5,
        "vinyasa yoga": 4.0,
        "power yoga": 4.0,
        "pilates": 3.0,
        
        "dancing": 4.5,
        "dans": 4.5,
        "dance": 4.5,
        "ballet": 4.8,
        "bale": 4.8,
        "hip hop": 5.0,
        "salsa": 5.0,
        "ballroom": 5.5,
        
        "boxing": 12.8,
        "boks": 12.8,
        "kickboxing": 10.3,
        "martial arts": 10.3,
        "karate": 10.3,
        "taekwondo": 10.3,
        "judo": 10.3,
        
        "kayaking": 5.0,
        "rowing": 7.0,
        "kürek": 7.0,
        "surfing": 3.0,
        "paddleboarding": 6.0,
        "water skiing": 6.0,
        
        "skiing": 7.0,
        "kayak": 7.0,
        "snowboarding": 5.3,
        "ice skating": 7.0,
        "buz pateni": 7.0,
        "cross-country skiing": 9.0,
        
        "climbing": 11.0,
        "tırmanış": 11.0,
        "rock climbing": 11.0,
        "rope jumping": 12.3,
        "ip atlama": 12.3,
        "jumping rope": 12.3,
        "elliptical": 5.0,
        "stair climbing": 8.8,
        "merdiven": 8.8,
        "rowing machine": 7.0,
        "golfing": 4.8,
        "golf": 4.8,
        "bowling": 3.0,
        "skateboarding": 5.0,
        "kaykay": 5.0,
        "rollerblading": 7.5,
        "paten": 7.5,
        
        "gardening": 4.0,
        "bahçe": 4.0,
        "mowing lawn": 5.5,
        "çim biçme": 5.5,
        "cleaning": 3.5,
        "temizlik": 3.5,
        "vacuuming": 3.5,
        "carrying groceries": 7.5,
        "alışveriş taşıma": 7.5,
        
        "playing with kids": 4.0,
        "çocuk oyunu": 4.0,
        "carrying children": 3.5,
        "çocuk taşıma": 3.5
    ]
    
    static func getMET(for activity: String) -> Double {
        let activityLower = activity.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let met = metValues[activityLower] {
            return met
        }
        
        for (key, value) in metValues {
            if activityLower.contains(key) || key.contains(activityLower) {
                return value
            }
        }
        
        return 5.0
    }
}

