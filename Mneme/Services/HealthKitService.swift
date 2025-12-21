import Foundation
import HealthKit
import Combine

final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()
    
    private let healthStore = HKHealthStore()
    @Published private(set) var authorizationStatus: HKAuthorizationStatus = .notDetermined
    
    private init() {
        if HKHealthStore.isHealthDataAvailable() {
            let hasRequested = UserDefaults.standard.bool(forKey: "hasRequestedHealthKitAuthorization")
            if hasRequested {
                authorizationStatus = .sharingAuthorized
            }
        }
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .height)!,
            HKQuantityType.quantityType(forIdentifier: .bodyMass)!,
            HKCharacteristicType.characteristicType(forIdentifier: .dateOfBirth)!,
            HKCharacteristicType.characteristicType(forIdentifier: .biologicalSex)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        ]
        
        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            await MainActor.run {
                UserDefaults.standard.set(true, forKey: "hasRequestedHealthKitAuthorization")
                authorizationStatus = .sharingAuthorized
            }
            return true
        } catch {
            return false
        }
    }
    
    var isAuthorized: Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        return UserDefaults.standard.bool(forKey: "hasRequestedHealthKitAuthorization")
    }
    
    // MARK: - Step Count
    
    func getStepCount(for date: Date) async -> Double? {
        guard isAuthorized else { return nil }
        
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let startDate = Calendar.current.startOfDay(for: date)
        let endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }
                
                let steps = result?.sumQuantity()?.doubleValue(for: HKUnit.count())
                
                if let steps = steps {
                    Task {
                        await DailyHealthStore.shared.saveMetric(date: startDate, stepCount: steps)
                    }
                }
                
                continuation.resume(returning: steps)
            }
            
            healthStore.execute(query)
        }
    }
    
    func getStepCountRange(startDate: Date, endDate: Date, interval: Calendar.Component = .day) async -> [Date: Double] {
        guard isAuthorized else { return [:] }
        
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        
        var intervalComponents = DateComponents()
        switch interval {
        case .day:
            intervalComponents.day = 1
        case .weekOfYear:
            intervalComponents.weekOfYear = 1
        default:
            intervalComponents.day = 1
        }
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startDate,
                intervalComponents: intervalComponents
            )
            
            query.initialResultsHandler = { _, results, error in
                if error != nil {
                    continuation.resume(returning: [:])
                    return
                }
                
                var stepCounts: [Date: Double] = [:]
                results?.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                    if let quantity = statistics.sumQuantity() {
                        let steps = quantity.doubleValue(for: HKUnit.count())
                        stepCounts[statistics.startDate] = steps
                    }
                }
                
                continuation.resume(returning: stepCounts)
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Active Energy (Calories)
    
    func getActiveEnergyBurned(for date: Date) async -> Double? {
        guard isAuthorized else { return nil }
        
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let startDate = Calendar.current.startOfDay(for: date)
        let endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: energyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }
                
                let calories = result?.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie())
                
                if let calories = calories {
                    Task {
                        await DailyHealthStore.shared.saveMetric(date: startDate, activeEnergy: calories)
                    }
                }
                
                continuation.resume(returning: calories)
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Height
    
    func getHeight() async -> Double? {
        guard isAuthorized else { return nil }
        
        let heightType = HKQuantityType.quantityType(forIdentifier: .height)!
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let height = sample.quantity.doubleValue(for: HKUnit.meter())
                continuation.resume(returning: height)
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Weight
    
    func getWeight() async -> Double? {
        guard isAuthorized else { return nil }
        
        let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: weightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let weight = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
                continuation.resume(returning: weight)
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Age
    
    func getAge() async -> Int? {
        guard isAuthorized else { return nil }
        
        do {
            let dateOfBirth = try healthStore.dateOfBirthComponents()
            let calendar = Calendar.current
            let today = Date()
            let ageComponents = calendar.dateComponents([.year], from: dateOfBirth.date ?? today, to: today)
            return ageComponents.year
        } catch {
            return nil
        }
    }
    
    // MARK: - Biological Sex
    
    func getBiologicalSex() async -> HKBiologicalSex? {
        guard isAuthorized else { return nil }
        
        do {
            let biologicalSex = try healthStore.biologicalSex()
            return biologicalSex.biologicalSex
        } catch {
            return nil
        }
    }
    
    // MARK: - Distance
    
    func getDistanceWalkingRunning(for date: Date) async -> Double? {
        guard isAuthorized else { return nil }
        
        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        let startDate = Calendar.current.startOfDay(for: date)
        let endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: distanceType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if error != nil {
                    continuation.resume(returning: nil)
                    return
                }
                
                let distance = result?.sumQuantity()?.doubleValue(for: HKUnit.meter())
                
                if let distance = distance {
                    Task {
                        await DailyHealthStore.shared.saveMetric(date: startDate, distance: distance)
                    }
                }
                
                continuation.resume(returning: distance)
            }
            
            healthStore.execute(query)
        }
    }
    
    // MARK: - Hourly Data
    
    func getStepCountHourly(for date: Date) async -> [Date: Double] {
        guard isAuthorized else { return [:] }
        
        let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let startDate = Calendar.current.startOfDay(for: date)
        let endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startDate,
                intervalComponents: DateComponents(hour: 1)
            )
            
            query.initialResultsHandler = { _, results, error in
                if error != nil {
                    continuation.resume(returning: [:])
                    return
                }
                
                var stepCounts: [Date: Double] = [:]
                results?.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                    if let quantity = statistics.sumQuantity() {
                        let steps = quantity.doubleValue(for: HKUnit.count())
                        stepCounts[statistics.startDate] = steps
                    }
                }
                
                continuation.resume(returning: stepCounts)
            }
            
            healthStore.execute(query)
        }
    }
    
    func getActiveEnergyHourly(for date: Date) async -> [Date: Double] {
        guard isAuthorized else { return [:] }
        
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let startDate = Calendar.current.startOfDay(for: date)
        let endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: energyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startDate,
                intervalComponents: DateComponents(hour: 1)
            )
            
            query.initialResultsHandler = { _, results, error in
                if error != nil {
                    continuation.resume(returning: [:])
                    return
                }
                
                var energyCounts: [Date: Double] = [:]
                results?.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                    if let quantity = statistics.sumQuantity() {
                        let energy = quantity.doubleValue(for: HKUnit.kilocalorie())
                        energyCounts[statistics.startDate] = energy
                    }
                }
                
                continuation.resume(returning: energyCounts)
            }
            
            healthStore.execute(query)
        }
    }
    
    func getDistanceHourly(for date: Date) async -> [Date: Double] {
        guard isAuthorized else { return [:] }
        
        let distanceType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        let startDate = Calendar.current.startOfDay(for: date)
        let endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: distanceType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startDate,
                intervalComponents: DateComponents(hour: 1)
            )
            
            query.initialResultsHandler = { _, results, error in
                if error != nil {
                    continuation.resume(returning: [:])
                    return
                }
                
                var distanceCounts: [Date: Double] = [:]
                results?.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                    if let quantity = statistics.sumQuantity() {
                        let distance = quantity.doubleValue(for: HKUnit.meter())
                        distanceCounts[statistics.startDate] = distance
                    }
                }
                
                continuation.resume(returning: distanceCounts)
            }
            
            healthStore.execute(query)
        }
    }
}

