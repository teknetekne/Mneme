import SwiftUI

/// Analysis tab wrapper for integration with chart tabs
struct AnalysisTab: View {
    @StateObject private var workSessionStore = WorkSessionStore.shared
    @StateObject private var notepadEntryStore = NotepadEntryStore.shared
    @StateObject private var currencySettingsStore = CurrencySettingsStore.shared
    @StateObject private var healthKitService = HealthKitService.shared
    
    var body: some View {
        AnalysisTabView(
            workSessionStore: workSessionStore,
            notepadEntryStore: notepadEntryStore,
            currencySettingsStore: currencySettingsStore,
            healthKitService: healthKitService
        )
    }
}

#Preview {
    NavigationStack {
        AnalysisTab()
    }
}

