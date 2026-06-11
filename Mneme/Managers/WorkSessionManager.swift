import Foundation
import Combine

enum WorkStartHandlingResult {
    case started
    case needsConfirmation
}

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
    var store: WorkSessionStore { workSessionStore }
    
    // MARK: - Initialization
    
    init(workSessionStore: WorkSessionStore? = nil) {
        self.workSessionStore = workSessionStore ?? .shared
    }
    
    // MARK: - Work Start
    
    /// Handle work session start
    /// - Parameters:
    ///   - result: Parsed NLP result
    ///   - originalText: Original text input
    func handleWorkStart(result: ParsedResult, originalText: String) async throws -> WorkStartHandlingResult {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let timeString = String(format: "%02d:%02d", hour, minute)
        let object = result.object?.value
        
        // Check if there's an existing active session
        if let existing = workSessionStore.getActiveWorkSession() {
            existingWorkSession = existing
            pendingWorkStart = (date: now, time: timeString, object: object)
            showWorkSessionConfirmation = true
            return .needsConfirmation
        } else {
            try await startNewSession(date: now, time: timeString, object: object)
            return .started
        }
    }
    
    /// Confirm work start replacement (called from confirmation dialog)
    func confirmWorkStartReplacement() async throws {
        guard let pending = pendingWorkStart else { return }
        
        guard let existing = existingWorkSession else {
            throw WorkSessionError.noActiveSession
        }

        _ = try await workSessionStore.replaceActiveSession(
            existingSessionId: existing.id,
            newDate: pending.date,
            newTime: pending.time,
            newObject: pending.object
        )
        
        showWorkSessionConfirmation = false
        pendingWorkStart = nil
        existingWorkSession = nil
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
        
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let timeString = String(format: "%02d:%02d", hour, minute)
        
        guard try await workSessionStore.recordWorkEnd(date: activeSession.date, time: timeString, object: activeSession.object) != nil else {
            throw WorkSessionError.noActiveSession
        }
    }
    
    // MARK: - Private Helpers
    
    /// Start a new work session
    private func startNewSession(date: Date, time: String, object: String?) async throws {
        let result = try await workSessionStore.recordWorkStart(date: date, time: time, object: object)
        if case .needsConfirmation = result {
            throw WorkSessionError.sessionAlreadyActive
        }
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
