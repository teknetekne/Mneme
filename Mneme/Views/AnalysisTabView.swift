import SwiftUI

struct AnalysisTabView: View {
    @ObservedObject var workSessionStore: WorkSessionStore
    @ObservedObject var notepadEntryStore: NotepadEntryStore
    @ObservedObject var currencySettingsStore: CurrencySettingsStore
    @ObservedObject var healthKitService: HealthKitService
    
    @State private var result: SummaryInsightResult?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var lastUpdated: Date?
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if isLoading {
                loadingView
            } else if let errorMessage {
                errorView(message: errorMessage)
            } else if let result {
                contentView(result)
            } else {
                emptyStateView
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        #if os(iOS)
        .background(Color.appBackground(colorScheme: colorScheme))
        #endif
        .navigationTitle("Analysis")
        .onAppear(perform: refreshIfNeeded)
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                refreshButton
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                refreshButton
            }
            #endif
        }
    }
    
    private var loadingView: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Discovering insights...")
                .foregroundStyle(.secondary)
                .font(.system(.subheadline, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 40)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text("Unable to analyze")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Not Enough Data")
                .font(.title3.weight(.semibold))
            Text("Add more daily entries to see patterns between your mood, work, and health.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
    
    private func contentView(_ result: SummaryInsightResult) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            // Overview Section
            VStack(alignment: .leading, spacing: 16) {

                Text(result.overview)
                    .font(.body) // Standard body font
                    .lineSpacing(6)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Divider()
            
            // Highlights Section
            if !result.highlights.isEmpty {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Key Observations")
                        .font(.title3.weight(.semibold)) // Standard title font
                        .foregroundStyle(.primary)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(result.highlights, id: \.self) { item in
                            HStack(alignment: .top, spacing: 16) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 8)
                                
                                Text(item)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(4)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func insightCard(_ result: SummaryInsightResult) -> some View {
        EmptyView() // Deprecated
    }
    
    private func refreshIfNeeded() {
        if result == nil && !isLoading {
            refresh(force: false)
        }
    }
    
    private func refresh(force: Bool) {
        guard !isLoading else { return }
        if !force, result != nil { return }
        isLoading = true
        errorMessage = nil
        
        Task {
            let newResult = await SummaryInsightsService.shared.analyze(
                days: 30,
                workSessionStore: workSessionStore,
                notepadEntryStore: notepadEntryStore,
                currencySettingsStore: currencySettingsStore,
                healthKitService: healthKitService
            )
            
            await MainActor.run {
                self.result = newResult
                self.lastUpdated = Date()
                self.isLoading = false
            }
        }
    }
    
    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        DateHelper.applySettings(formatter)
        return formatter.string(from: date)
    }
    
    private var refreshButton: some View {
        Button {
            refresh(force: true)
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .disabled(isLoading)
    }
}
