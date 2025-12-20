//
//  MnemeApp.swift
//  Mneme
//
//  Created by Emre Tekneci on 3.11.2025.
//

import SwiftUI

@main
@MainActor
struct MnemeApp: App {
    private let persistenceController = PersistenceController.shared
    private let cloudSyncStatus = CloudSyncStatusStore.shared
    private let tagStore = TagStore.shared

    init() {
        HapticHelper.prepareHapticEngine()
        _ = cloudSyncStatus
        _ = tagStore
        
        // Refresh currency rates on launch
        Task {
            await CurrencyService.shared.refreshRates()
        }
    }
    
    @ObservedObject private var userSettings = UserSettingsStore.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.viewContext)
                .environmentObject(cloudSyncStatus)
                .environmentObject(tagStore)
                .preferredColorScheme(userSettings.appTheme.colorScheme)
        }
    }
}
