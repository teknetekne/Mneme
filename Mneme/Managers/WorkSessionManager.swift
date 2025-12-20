import Foundation
import Combine

// MARK: - Work Session Manager

/// Manages work session tracking (start/end)
/// Responsibility: Handle work session state and confirmations
@MainActor
final class WorkSessionManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var showWorkSessionConfirmation = false
    @Published var pendingWorkStart: (date: Date, time: String, object: String?)? = nil
    @Published var existingWorkSession: WorkSessionStruct? = nil
    
    // MARK: - Dependencies
    
    private let workSessionStore: WorkSessionStore
    
    // MARK: - Initialization
    
    init(workSessionStore: WorkSessionStore? = nil) {
        self.workSessionStore = workSessionStore ?? .shared
    }
    
    // MARK: - Work Start
    
    /// Handle work session start
    /// - Parameters:
    ///   - result: Parsed NLP result
    ///   - originalText: Original text input
    func handleWorkStart(result: ParsedResult, originalText: String) async throws {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let timeString = String(format: "%02d:%02d", hour, minute)
        let object = result.object?.value
        
        // Check if there's an existing active session
        if let existing = workSessionStore.getActiveWorkSession() {
            // Show confirmation dialog
            await MainActor.run {
                self.existingWorkSession = existing
                self.pendingWorkStart = (date: now, time: timeString, object: object)
                self.showWorkSessionConfirmation = true
            }
        } else {
            // No active session - start new one directly
            try await startNewSession(date: now, time: timeString, object: object)
        }
    }
    
    /// Confirm work start replacement (called from confirmation dialog)
    func confirmWorkStartReplacement() async throws {
        guard let pending = pendingWorkStart else { return }
        
        // End existing session
        if let existing = existingWorkSession {
            _ = workSessionStore.recordWorkEnd(date: pending.date, time: pending.time, object: existing.object)
        }
        
        // Start new session
        try await startNewSession(
            date: pending.date,
            time: pending.time,
            object: pending.object
        )
        
        // Clear state
        await MainActor.run {
            self.showWorkSessionConfirmation = false
            self.pendingWorkStart = nil
            self.existingWorkSession = nil
        }
    }
    
    /// Cancel work start replacement
    func cancelWorkStartReplacement() {
        showWorkSessionConfirmation = false
        pendingWorkStart = nil
        existingWorkSession = nil
    }
    
    // MARK: - Work End
    
    /// Handle work session end
    /// - Parameters:
    ///   - result: Parsed NLP result
    ///   - originalText: Original text input
    func handleWorkEnd(result: ParsedResult, originalText: String) async throws {
        guard let activeSession = workSessionStore.getActiveWorkSession() else {
            // No active session to end
            throw WorkSessionError.noActiveSession
        }
        
        let endDate = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: endDate)
        let minute = calendar.component(.minute, from: endDate)
        let timeString = String(format: "%02d:%02d", hour, minute)
        
        _ = workSessionStore.recordWorkEnd(date: endDate, time: timeString, object: activeSession.object)
    }
    
    // MARK: - Private Helpers
    
    /// Start a new work session
    private func startNewSession(date: Date, time: String, object: String?) async throws {
        _ = workSessionStore.recordWorkStart(date: date, time: time, object: object)
    }
    
    // MARK: - Queries
    
    /// Get active work session
    var activeSession: WorkSessionStruct? {
        workSessionStore.getActiveWorkSession()
    }
    
    /// Check if there's an active session
    var hasActiveSession: Bool {
        workSessionStore.getActiveWorkSession() != nil
    }
}

// MARK: - Work Session Error

enum WorkSessionError: Error {
    case noActiveSession
    case sessionAlreadyActive
    
    var localizedDescription: String {
        switch self {
        case .noActiveSession:
            return "No active work session to end"
        case .sessionAlreadyActive:
            return "Work session already active"
        }
    }
}
