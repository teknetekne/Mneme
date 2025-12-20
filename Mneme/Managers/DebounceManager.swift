import Foundation

// MARK: - Debounce Manager

/// Manages debounced task execution for text parsing
/// Responsibility: Schedule, cancel, and track debounced parsing tasks
@MainActor
final class DebounceManager {
    
    // MARK: - Properties
    
    /// Debounce delay in nanoseconds (default: 1.5 seconds)
    private let debounceDelay: UInt64
    
    /// Active debounce tasks keyed by line UUID
    private var debounceTasks: [UUID: Task<Void, Never>] = [:]
    
    // MARK: - Initialization
    
    /// Initialize with custom debounce delay
    /// - Parameter debounceDelayMs: Delay in milliseconds (default: 1500ms = 1.5s)
    init(debounceDelayMs: UInt64 = 1500) {
        self.debounceDelay = debounceDelayMs * 1_000_000 // Convert ms to nanoseconds
    }
    
    // MARK: - Public Methods
    
    /// Schedule a debounced task
    /// - Parameters:
    ///   - id: UUID of the line to associate with the task
    ///   - action: Async closure to execute after debounce delay
    func schedule(for id: UUID, action: @escaping @MainActor () async -> Void) {
        // Cancel any existing task for this line
        cancel(for: id)
        
        // Create new debounced task
        let task = Task { @MainActor in
            // Wait for debounce delay
            try? await Task.sleep(nanoseconds: debounceDelay)
            
            // Check if task was cancelled during sleep
            guard !Task.isCancelled else {
                return
            }
            
            // Execute the action
            await action()
            
            // Clean up task from dictionary
            let _ = await MainActor.run {
                debounceTasks.removeValue(forKey: id)
            }
        }
        
        // Store task
        debounceTasks[id] = task
    }
    
    /// Cancel a debounced task for a specific line
    /// - Parameter id: UUID of the line
    func cancel(for id: UUID) {
        debounceTasks[id]?.cancel()
        debounceTasks.removeValue(forKey: id)
    }
    
    /// Cancel all active debounce tasks
    func cancelAll() {
        for task in debounceTasks.values {
            task.cancel()
        }
        debounceTasks.removeAll()
    }
    
    /// Check if there's an active debounce task for a line
    /// - Parameter id: UUID of the line
    /// - Returns: True if task exists and is not cancelled
    func hasActiveTask(for id: UUID) -> Bool {
        guard let task = debounceTasks[id] else {
            return false
        }
        return !task.isCancelled
    }
    
    /// Get count of active debounce tasks
    var activeTaskCount: Int {
        debounceTasks.count
    }
}
