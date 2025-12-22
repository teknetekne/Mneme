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
    
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 24) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                
                Text("Permissions Setup")
                    .font(.title.bold())
                
                Text("To provide the best experience, we need access to your health and calendar data.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                VStack(spacing: 16) {
                    permissionRow(
                        icon: "heart.fill",
                        iconColor: .red,
                        title: "Health Data",
                        description: "Access your steps, calories, height, weight, and age",
                        isAuthorized: healthKitAuthorized,
                        isLoading: isRequestingHealthKit,
                        action: requestHealthKitPermission
                    )
                    
                    permissionRow(
                        icon: "calendar",
                        iconColor: .blue,
                        title: "Calendar & Reminders",
                        description: "Access your events and reminders",
                        isAuthorized: eventKitAuthorized,
                        isLoading: isRequestingEventKit,
                        action: requestEventKitPermission
                    )
                }
                .padding(.horizontal, 32)
                
                Button {
                    onComplete()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
            }
            
            Spacer()
        }
        .onAppear {
            checkPermissions()
        }
        .onChange(of: healthKitService.authorizationStatus) { _, newStatus in
            // Check authorization status after it changes
            Task { @MainActor in
                healthKitAuthorized = healthKitService.isAuthorized
            }
        }
        .onChange(of: eventKitService.authorizationStatus) { _, newStatus in
            Task { @MainActor in
                eventKitAuthorized = eventKitService.isAuthorized
            }
        }
    }
    
    private func permissionRow(
        icon: String,
        iconColor: Color,
        title: String,
        description: String,
        isAuthorized: Bool,
        isLoading: Bool,
        action: @escaping () -> Void
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
            } else {
                Button {
                    action()
                } label: {
                    Text("Continue")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding()
        .background(Color(white: 0, opacity: 0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private func checkPermissions() {
        healthKitAuthorized = healthKitService.isAuthorized
        eventKitAuthorized = eventKitService.isAuthorized
    }
    
    private func requestHealthKitPermission() {
        isRequestingHealthKit = true
        Task {
            _ = await healthKitService.requestAuthorization()
            await MainActor.run {
                // Force check authorization status after request
                healthKitAuthorized = healthKitService.isAuthorized
                isRequestingHealthKit = false
                
                // Also check after a short delay to ensure status is updated
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                    await MainActor.run {
                        healthKitAuthorized = healthKitService.isAuthorized
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
            }
        }
    }
    
}
