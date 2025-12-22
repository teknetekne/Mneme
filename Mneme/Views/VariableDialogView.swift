import SwiftUI

struct VariableDialogView: View {
    private enum MealUnit: String, CaseIterable, Identifiable {
        case g = "g"
        case kg = "kg"
        case oz = "oz"
        case lb = "lb"
        
        var id: String { rawValue }
        
        func toGrams(_ value: Double) -> Double {
            switch self {
            case .g: return value
            case .kg: return value * 1000
            case .oz: return value * 28.3495
            case .lb: return value * 453.592
            }
        }
    }
    
    @Binding var isPresented: Bool
    @ObservedObject var variableStore: VariableStore
    @ObservedObject private var currencySettings = CurrencySettingsStore.shared
    
    @State private var variableType: VariableType = .expense
    @State private var variableName: String = ""
    @State private var variableValue: String = ""
    @State private var variableGrams: String = ""
    @State private var selectedUnit: MealUnit = .g
    @State private var selectedCurrency: String? = nil
    @State private var searchText: String = ""
    @Namespace private var namespace
    
    private var secondaryGroupedBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
    
    private var systemBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                #if os(iOS)
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                #else
                Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
                #endif
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Creation Card
                        VStack(spacing: 20) {
                            // Type Selector
                            HStack(spacing: 0) {
                                ForEach(VariableType.allCases, id: \.self) { type in
                                    Button {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            variableType = type
                                            // Set currency to base currency for expense/income
                                            if type == .expense || type == .income {
                                                selectedCurrency = currencySettings.baseCurrency
                                            } else {
                                                selectedCurrency = nil
                                            }
                                        }
                                    } label: {
                                        VStack(spacing: 6) {
                                            Image(systemName: iconForType(type))
                                                .font(.system(size: 16, weight: .medium))
                                            Text(type.displayName)
                                                .font(.system(size: 12, weight: .medium))
                                        }
                                        .foregroundStyle(variableType == type ? .white : .secondary)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 60)
                                        .background {
                                            if variableType == type {
                                                RoundedRectangle(cornerRadius: 12)
                                                    .fill(Color.accentColor)
                                                    .matchedGeometryEffect(id: "activeTab", in: namespace)
                                            }
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(4)
                            .background(secondaryGroupedBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
                            
                            // Input Fields
                            VStack(spacing: 16) {
                                // Name Field
                                HStack {
                                    Image(systemName: "tag.fill")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)
                                    TextField("Name", text: $variableName)
                                        #if os(iOS)
                                        .textInputAutocapitalization(.never)
                                        #endif
                                        .autocorrectionDisabled()
                                }
                                .padding()
                                .background(secondaryGroupedBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                                )
                                
                                if variableType == .meal {
                                    HStack(spacing: 12) {
                                        // Calories
                                        HStack {
                                            Image(systemName: "flame.fill")
                                                .foregroundStyle(.orange)
                                                .frame(width: 24)
                                            TextField("Calories", text: $variableValue)
                                                #if os(iOS)
                                                .keyboardType(.numberPad)
                                                #endif
                                            Text("kcal")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .padding()
                                        .background(secondaryGroupedBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                                        )
                                        
                                        // Grams
                                        HStack {
                                            Image(systemName: "scalemass.fill")
                                                .foregroundStyle(.blue)
                                                .frame(width: 24)
                                            TextField("Size", text: $variableGrams)
                                                #if os(iOS)
                                                .keyboardType(.decimalPad)
                                                #endif
                                            
                                            Menu {
                                                ForEach(MealUnit.allCases) { unit in
                                                    Button(unit.rawValue) {
                                                        selectedUnit = unit
                                                    }
                                                }
                                            } label: {
                                                Text(selectedUnit.rawValue)
                                                    .font(.caption.bold())
                                                    .foregroundStyle(Color.accentColor)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.accentColor.opacity(0.1))
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        .padding()
                                        .background(secondaryGroupedBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                                        )
                                    }
                                } else {
                                    // Amount & Currency
                                    HStack {
                                        Image(systemName: variableType == .income ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                            .foregroundStyle(variableType == .income ? .green : .red)
                                            .frame(width: 24)
                                        
                                        TextField("Amount", text: $variableValue)
                                            #if os(iOS)
                                            .keyboardType(.decimalPad)
                                            #endif
                                        
                                        Menu {
                                            ForEach(Currency.all) { currency in
                                                Button("\(currency.code) (\(currency.symbol))") {
                                                    selectedCurrency = currency.code
                                                }
                                            }
                                            Button("None") {
                                                selectedCurrency = nil
                                            }
                                        } label: {
                                            Text(selectedCurrency ?? "Currency")
                                                .font(.caption.bold())
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.accentColor.opacity(0.1))
                                                .foregroundStyle(Color.accentColor)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    .padding()
                                    .background(secondaryGroupedBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                                    )
                                }
                            }
                            
                            // Example Text
                            HStack {
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                Text(exampleText(for: variableType))
                                    .font(.caption)
                                Spacer()
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            
                            // Add Button
                            Button {
                                addVariable()
                            } label: {
                                Text("Add Variable")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(isValidInput ? Color.accentColor : Color.secondary.opacity(0.3))
                                    )
                            }
                            .disabled(!isValidInput)
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal)
                        
                        // Existing Variables List
                        if !variableStore.variables.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("Existing Variables")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal)
                                
                                // Search Bar
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(.secondary)
                                    TextField("Search variables...", text: $searchText)
                                        .textFieldStyle(.plain)
                                    if !searchText.isEmpty {
                                        Button {
                                            searchText = ""
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(10)
                                .background(secondaryGroupedBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .padding(.horizontal)
                                
                                LazyVStack(spacing: 12) {
                                    let filteredVariables = variableStore.variables.filter { variable in
                                        searchText.isEmpty || variable.name.localizedCaseInsensitiveContains(searchText)
                                    }
                                    
                                    ForEach(filteredVariables) { variable in
                                        HStack(spacing: 16) {
                                            // Icon
                                            ZStack {
                                                Circle()
                                                    .fill(colorForType(variable.type).opacity(0.1))
                                                    .frame(width: 40, height: 40)
                                                Image(systemName: iconForType(variable.type))
                                                    .foregroundStyle(colorForType(variable.type))
                                            }
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(variable.name)
                                                    .font(.subheadline.weight(.semibold))
                                                
                                                HStack(spacing: 6) {
                                                    if variable.type == .meal {
                                                        if let calories = variable.calories {
                                                            Text("\(Int(calories)) kcal")
                                                                .foregroundStyle(.secondary)
                                                        }
                                                        if let grams = variable.grams {
                                                            Text("• \(Int(grams))g")
                                                                .foregroundStyle(.tertiary)
                                                        }
                                                    } else {
                                                        if let amount = variable.amount ?? Double(variable.value) {
                                                            Text("\(String(format: "%.2f", amount))")
                                                                .foregroundStyle(.secondary)
                                                        }
                                                        if let currency = variable.currency {
                                                            Text(currency)
                                                                .foregroundStyle(.tertiary)
                                                        }
                                                    }
                                                }
                                                .font(.caption)
                                            }
                                            
                                            Spacer()
                                            
                                            Button {
                                                withAnimation {
                                                    variableStore.deleteVariable(variable)
                                                }
                                            } label: {
                                                Image(systemName: "trash")
                                                    .font(.system(size: 14))
                                                    .foregroundStyle(.red.opacity(0.6))
                                                    .padding(8)
                                                    .background(Color.red.opacity(0.1))
                                                    .clipShape(Circle())
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding()
                                        .background(secondaryGroupedBackground)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Variables")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
        .onAppear {
            // Initialize currency to base currency for expense/income on first load
            if (variableType == .expense || variableType == .income) && selectedCurrency == nil {
                selectedCurrency = currencySettings.baseCurrency
            }
        }
    }
    
    private var isValidInput: Bool {
        !variableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !variableValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func iconForType(_ type: VariableType) -> String {
        switch type {
        case .expense: return "arrow.down.circle.fill"
        case .income: return "arrow.up.circle.fill"
        case .meal: return "fork.knife.circle.fill"
        }
    }
    
    private func colorForType(_ type: VariableType) -> Color {
        switch type {
        case .expense: return .red
        case .income: return .green
        case .meal: return .orange
        }
    }
    
    private func exampleText(for type: VariableType) -> String {
        switch type {
        case .expense: return "Example: Rent, Netflix, Gym"
        case .income: return "Example: Salary, Freelance, Bonus"
        case .meal: return "Example: Pizza, Burger, Salad"
        }
    }
    
    private func addVariable() {
        let name = variableName.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = variableValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !name.isEmpty, !value.isEmpty else { return }
        
        if variableType == .meal {
            let calories = Double(value)
            // Convert input to double, default to 0 if invalid
            let rawGrams = Double(variableGrams.trimmingCharacters(in: .whitespacesAndNewlines))
            
            // Convert to grams based on selected unit if rawGrams exists
            let grams: Double?
            if let raw = rawGrams {
                 grams = selectedUnit.toGrams(raw)
            } else {
                grams = nil
            }
            
            let jsonValue = VariableStruct.createValueString(calories: calories, grams: grams)
            variableStore.addVariable(name: name, value: jsonValue, type: variableType)
        } else {
            // For expense/income, we can just store the amount directly in value for now,
            // or use the new JSON structure if we want to be consistent.
            // But to match previous logic which might expect a simple string for amount:
            // Actually, let's use the new structure for everything to be safe, or stick to string for backward compat?
            // The previous implementation used simple string for expense/income.
            // Let's stick to that for now unless we need more fields.
            
            // Wait, the previous implementation I wrote in VariableStore handles this.
            // If I pass a simple string, it treats it as amount.
            
            // However, I should check if I need to extract currency.
            // The TextParsingHelpers.extractCurrency might be useful here if the user typed "100 USD"
            // But here we have a numeric keyboard for amount.
            
            variableStore.addVariable(name: name, value: value, type: variableType, currency: selectedCurrency)
        }
        
        // Reset fields
        variableName = ""
        variableValue = ""
        variableGrams = ""
        selectedUnit = .g // Reset unit to default
        // Reset currency to base currency if expense/income
        if variableType == .expense || variableType == .income {
            selectedCurrency = currencySettings.baseCurrency
        } else {
            selectedCurrency = nil
        }
    }
}
