import SwiftUI
import EventKit
import HealthKit

struct PermissionsOnboardingView: View {
    @StateObject private var healthKitService = HealthKitService.shared
    @StateObject private var eventKitService = EventKitService.shared
    
    @State private var healthKitAuthorized = false
    @State private var eventKitAuthorized = false
    @State private var isRequestingHealthKit = false
    @State private var isRequestingEventKit = false
    
    // New state for tracking stages
    enum PermissionStage {
        case health
        case calendar
    }
    @State private var currentStage: PermissionStage = .health
    
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 24) {
                // Dynamic Icon based on stage
                Image(systemName: currentStage == .health ? "heart.fill" : "calendar")
                    .font(.system(size: 64))
                    .foregroundStyle(currentStage == .health ? .red : .blue)
                    .padding(.bottom, 8)
                    .transition(.scale.combined(with: .opacity))
                    .id(currentStage) // Force transition
                
                Text(currentStage == .health ? "Health Access" : "Calendar Access")
                    .font(.title.bold())
                    .transition(.opacity)
                    .id("title-\(currentStage)")
                
                Text(currentStage == .health
                     ? "Mneme needs access to your health data to track personal health metrics and biological information. You can choose what to share on the next screen."
                     : "Mneme needs access to your calendar and reminders to help you organize your schedule effectively. You can choose what to share on the next screen.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .transition(.opacity)
                    .id("desc-\(currentStage)")
                
                // Content View for Validating Permissions
                VStack(spacing: 16) {
                    if currentStage == .health {
                        permissionStatusRow(
                            icon: "heart.fill",
                            iconColor: .red,
                            title: "Health Data",
                            description: "Steps, calories, biology",
                            isAuthorized: healthKitAuthorized,
                            isLoading: isRequestingHealthKit
                        )
                    } else {
                        permissionStatusRow(
                            icon: "calendar",
                            iconColor: .blue,
                            title: "Calendar & Reminders",
                            description: "Events, tasks, scheduling",
                            isAuthorized: eventKitAuthorized,
                            isLoading: isRequestingEventKit
                        )
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                
                Button {
                    handleContinue()
                } label: {
                    Text(getButtonTitle())
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
                
                Button("Skip for now") {
                   handleSkip()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            }
            .animation(.easeInOut, value: currentStage)
            
            Spacer()
        }
        .onAppear {
            checkPermissions()
        }
        .onChange(of: healthKitService.authorizationStatus) { _, newStatus in
            Task { @MainActor in
                healthKitAuthorized = healthKitService.isAuthorized
                // Auto-advance if authorized
                if healthKitAuthorized && currentStage == .health {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    withAnimation {
                        currentStage = .calendar
                    }
                }
            }
        }
        .onChange(of: eventKitService.authorizationStatus) { _, newStatus in
            Task { @MainActor in
                eventKitAuthorized = eventKitService.isAuthorized
                // Auto-complete if authorized
                if eventKitAuthorized && currentStage == .calendar {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    onComplete()
                }
            }
        }
    }
    
    private func getButtonTitle() -> String {
        switch currentStage {
        case .health:
            return "Continue"
        case .calendar:
            return "Continue"
        }
    }
    
    private func handleContinue() {
        switch currentStage {
        case .health:
            if healthKitAuthorized {
                withAnimation {
                    currentStage = .calendar
                }
            } else {
                requestHealthKitPermission()
            }
        case .calendar:
            if eventKitAuthorized {
                onComplete()
            } else {
                requestEventKitPermission()
            }
        }
    }
    
    private func handleSkip() {
        switch currentStage {
        case .health:
            withAnimation {
                currentStage = .calendar
            }
        case .calendar:
            onComplete()
        }
    }
    
    private func permissionStatusRow(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        isAuthorized: Bool,
        isLoading: Bool
    ) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
            } else if isAuthorized {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                    .transition(.scale)
            }
        }
        .padding()
        .background(Color(white: 0, opacity: 0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func checkPermissions() {
        healthKitAuthorized = healthKitService.isAuthorized
        eventKitAuthorized = eventKitService.isAuthorized
        
        // If HealthKit is already authorized, start at calendar stage
        if healthKitAuthorized {
             currentStage = .calendar
        }
    }
    
    private func requestHealthKitPermission() {
        isRequestingHealthKit = true
        Task {
            _ = await healthKitService.requestAuthorization()
            await MainActor.run {
                healthKitAuthorized = healthKitService.isAuthorized
                isRequestingHealthKit = false
                
                if healthKitAuthorized {
                     withAnimation {
                         currentStage = .calendar
                     }
                }
            }
        }
    }
    
    private func requestEventKitPermission() {
        isRequestingEventKit = true
        Task {
            _ = await eventKitService.requestFullAccess()
            await MainActor.run {
                eventKitAuthorized = eventKitService.isAuthorized
                isRequestingEventKit = false
                
                if eventKitAuthorized {
                     onComplete()
                }
            }
        }
    }
}
