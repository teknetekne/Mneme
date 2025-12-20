import Foundation
import SwiftUI
import Combine
import HealthKit
import CoreData

final class UserSettingsStore: ObservableObject {
    static let shared = UserSettingsStore()
    
    @Published var height: Double?
    @Published var weight: Double?
    @Published var age: Int?
    @Published var biologicalSex: BiologicalSex = .notSet
    
    @AppStorage("unitSystem") var unitSystem: UnitSystem = .metric
    @AppStorage("timeFormat") var timeFormat: TimeFormat = .twentyFourHour
    @AppStorage("dateFormat") var dateFormat: AppDateFormat = .systemDefault
    @AppStorage("appTheme") var appTheme: AppTheme = .system
    
    private let context: NSManagedObjectContext
    private var profileEntity: UserProfileEntity?
    
    private init() {
        self.context = PersistenceController.shared.viewContext
        loadProfile()
        
        Task {
            if DataMigrationService.shared.needsMigration {
                try? await DataMigrationService.shared.performMigration()
            }
            loadProfile()
        }
    }
    
    @MainActor
    private func loadProfile() {
        let fetchRequest: NSFetchRequest<UserProfileEntity> = UserProfileEntity.fetchRequest()
        fetchRequest.fetchLimit = 1
        
        if let profile = try? context.fetch(fetchRequest).first {
            profileEntity = profile
            height = profile.heightCm != 0 ? profile.heightCm : nil
            weight = profile.weightKg != 0 ? profile.weightKg : nil
            age = profile.age != 0 ? Int(profile.age) : nil
            if let sexRaw = profile.biologicalSex,
               let sex = BiologicalSex(rawValue: sexRaw) {
                biologicalSex = sex
            }
        } else {
            // Create default profile
            let profile = UserProfileEntity(context: context)
            profile.id = UUID()
            profile.modifiedAt = Date()
            profileEntity = profile
            
            do {
                try context.save()
            } catch {
            }
        }
    }
    
    func setHeight(_ value: Double?) {
        height = value
        saveProfile()
    }
    
    func setWeight(_ value: Double?) {
        weight = value
        saveProfile()
    }
    
    func setAge(_ value: Int?) {
        age = value
        saveProfile()
    }
    
    func setBiologicalSex(_ value: BiologicalSex) {
        biologicalSex = value
        saveProfile()
    }
    
    private func saveProfile() {
        guard let coordinator = self.context.persistentStoreCoordinator else { return }
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        context.perform {
            let fetchRequest: NSFetchRequest<UserProfileEntity> = UserProfileEntity.fetchRequest()
            fetchRequest.fetchLimit = 1

            let profile: UserProfileEntity
            if let existing = (try? context.fetch(fetchRequest))?.first {
                profile = existing
            } else {
                let newProfile = UserProfileEntity(context: context)
                newProfile.id = UUID()
                profile = newProfile
            }

            profile.heightCm = self.height ?? 0
            profile.weightKg = self.weight ?? 0
            profile.age = Int32(self.age ?? 0)
            profile.biologicalSex = self.biologicalSex.rawValue
            profile.modifiedAt = Date()

            do {
                try context.save()
            } catch {
            }
        }
    }
    
    func loadFromHealthKit() async {
        let healthKitService = HealthKitService.shared
        
        guard healthKitService.isAuthorized else { return }
        
        if let hkHeight = await healthKitService.getHeight() {
            await MainActor.run {
                self.setHeight(hkHeight * 100)
            }
        }
        
        if let hkWeight = await healthKitService.getWeight() {
            await MainActor.run {
                self.setWeight(hkWeight)
            }
        }
        
        if let hkAge = await healthKitService.getAge() {
            await MainActor.run {
                self.setAge(hkAge)
            }
        }
        
        if let hkSex = await healthKitService.getBiologicalSex() {
            await MainActor.run {
                self.setBiologicalSex(BiologicalSex(from: hkSex))
            }
        }
    }
}

