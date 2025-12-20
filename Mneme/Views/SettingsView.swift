import SwiftUI
import HealthKit

struct SettingsView: View {
    @StateObject private var userSettingsStore = UserSettingsStore.shared
    @StateObject private var currencySettingsStore = CurrencySettingsStore.shared
    @StateObject private var healthKitService = HealthKitService.shared

    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var heightText: String = ""
    @State private var weightText: String = ""
    @State private var ageText: String = ""
    @State private var isLoadingFromHealthKit = false
    
    private var usesMetricSystem: Bool {
        userSettingsStore.unitSystem == .metric
    }
    
    private var heightLabel: String {
        usesMetricSystem ? "Height (cm)" : "Height (ft/in)"
    }
    
    private var weightLabel: String {
        usesMetricSystem ? "Weight (kg)" : "Weight (lbs)"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Personal Information") {
                    HStack {
                        Text(heightLabel)
                        Spacer()
                        TextField(usesMetricSystem ? "cm" : "ft/in", text: $heightText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            #endif
                            .frame(width: 100)
                    }
                    
                    HStack {
                        Text(weightLabel)
                        Spacer()
                        TextField(usesMetricSystem ? "kg" : "lbs", text: $weightText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            #endif
                            .frame(width: 100)
                    }
                    
                    HStack {
                        Text("Age")
                        Spacer()
                        TextField("Age", text: $ageText)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            #endif
                            .frame(width: 100)
                    }
                    
                    Picker("Sex", selection: $userSettingsStore.biologicalSex) {
                        ForEach(BiologicalSex.allCases, id: \.self) { sex in
                            Text(sex.displayName).tag(sex)
                        }
                    }
                    
                    if healthKitService.isAuthorized {
                        Button {
                            Task {
                                isLoadingFromHealthKit = true
                                await userSettingsStore.loadFromHealthKit()
                                updateTextFields()
                                isLoadingFromHealthKit = false
                            }
                        } label: {
                            HStack {
                                if isLoadingFromHealthKit {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("Load from HealthKit")
                            }
                        }
                    } else {
                        Button {
                            Task {
                                _ = await healthKitService.requestAuthorization()
                            }
                        } label: {
                            Text("Enable HealthKit Access")
                        }
                    }
                }
                
                Section("Currency") {
                    Picker("Base Currency", selection: Binding(
                        get: { currencySettingsStore.baseCurrency },
                        set: { currencySettingsStore.setBaseCurrency($0) }
                    )) {
                        Text("USD").tag("USD")
                        Text("EUR").tag("EUR")
                        Text("TRY").tag("TRY")
                        Text("GBP").tag("GBP")
                        Text("JPY").tag("JPY")
                        Text("CNY").tag("CNY")
                        Text("AUD").tag("AUD")
                        Text("CAD").tag("CAD")
                        Text("CHF").tag("CHF")
                        Text("INR").tag("INR")
                    }
                }
                
                Section("App Preferences") {
                    Picker("Unit System", selection: $userSettingsStore.unitSystem) {
                        ForEach(UnitSystem.allCases, id: \.self) { system in
                            Text(system.displayName).tag(system)
                        }
                    }
                    .onChange(of: userSettingsStore.unitSystem) { old, new in
                        updateTextFields()
                    }
                    
                    Picker("Time Format", selection: $userSettingsStore.timeFormat) {
                        ForEach(TimeFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    
                    Picker("Date Format", selection: $userSettingsStore.dateFormat) {
                        ForEach(AppDateFormat.allCases, id: \.self) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    
                    Picker("Theme", selection: $userSettingsStore.appTheme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                }
                

            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        saveSettings()
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button("Done") {
                        saveSettings()
                        dismiss()
                    }
                }
                #endif
            }
            .onAppear {
                updateTextFields()
            }
        }
    }
    
    private func updateTextFields() {
        if let height = userSettingsStore.height {
            if usesMetricSystem {
                heightText = String(format: "%.1f", height)
            } else {
                let (feet, inches) = UnitConversionHelper.centimetersToFeetInches(height)
                heightText = String(format: "%d' %.1f\"", feet, inches)
            }
        } else {
            heightText = ""
        }
        
        if let weight = userSettingsStore.weight {
            if usesMetricSystem {
                weightText = String(format: "%.1f", weight)
            } else {
                let lbs = UnitConversionHelper.kilogramsToPounds(weight)
                weightText = String(format: "%.1f", lbs)
            }
        } else {
            weightText = ""
        }
        
        if let age = userSettingsStore.age {
            ageText = String(age)
        } else {
            ageText = ""
        }
    }
    
    private func saveSettings() {
        // Parse height
        if let parsedHeight = parseHeight(heightText) {
            userSettingsStore.setHeight(parsedHeight)
        } else {
            userSettingsStore.setHeight(nil)
        }
        
        // Parse weight
        if let parsedWeight = parseWeight(weightText) {
            userSettingsStore.setWeight(parsedWeight)
        } else {
            userSettingsStore.setWeight(nil)
        }
        
        // Parse age
        if let age = Int(ageText), age > 0 {
            userSettingsStore.setAge(age)
        } else {
            userSettingsStore.setAge(nil)
        }
    }
    
    private func parseHeight(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        
        // Try parsing with UnitConversionHelper first
        if let parsed = UnitConversionHelper.parseHeight(from: trimmed) {
            return parsed.value
        }
        
        // Fallback: parse as number and convert based on locale
        if let value = Double(trimmed) {
            if usesMetricSystem {
                // Assume cm
                return value > 0 ? value : nil
            } else {
                // Assume feet (simple case, user can enter "5.83" for 5'10")
                // For more complex parsing, user should use format like "5'10\""
                if value > 0 && value < 10 {
                    // Likely feet only, convert to cm
                    return UnitConversionHelper.feetInchesToCentimeters(feet: Int(value), inches: (value - Double(Int(value))) * 12)
                }
                return nil
            }
        }
        
        return nil
    }
    
    private func parseWeight(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        
        // Try parsing with UnitConversionHelper first
        if let parsed = UnitConversionHelper.parseWeight(from: trimmed) {
            return parsed.value
        }
        
        // Fallback: parse as number and convert based on locale
        if let value = Double(trimmed) {
            if usesMetricSystem {
                // Assume kg
                return value > 0 ? value : nil
            } else {
                // Assume lbs, convert to kg
                return value > 0 ? UnitConversionHelper.poundsToKilograms(value) : nil
            }
        }
        
        return nil
    }
}


