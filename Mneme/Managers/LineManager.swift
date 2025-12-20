import Foundation
import SwiftUI
import Combine

// MARK: - Line Manager

/// Manages line lifecycle with array-based storage
/// Simple, direct array operations for SwiftUI ForEach binding
@MainActor
final class LineManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// All lines in display order - source of truth for SwiftUI binding
    @Published var lines: [LineViewModel] = []
    
    // MARK: - Initialization
    
    init() {
        // Start with one empty line
        let initialLine = LineViewModel(text: "")
        lines = [initialLine]
    }
    
    // MARK: - Line Updates
    
    /// Update text for a specific line
    func updateText(for id: UUID, newText: String) {
        guard let idx = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[idx].text = newText
    }
    
    /// Update status for a specific line
    func updateStatus(for id: UUID, status: ParseStatus) {
        guard let idx = lines.firstIndex(where: { $0.id == id }) else { return }
        
        // Skip if status hasn't changed (avoid unnecessary updates)
        guard lines[idx].status != status else { return }
        
        lines[idx].status = status
    }
    
    // MARK: - User Interaction Handlers
    
    /// Add a new line at the end (for focus management)
    func addLineAndFocus() -> UUID {
        let new = LineViewModel(text: "")
        lines.append(new)
        return new.id
    }
    
    /// Handle backspace on empty line - deletes line and returns previous line ID
    func handleBackspaceOnEmptyLine(for id: UUID, clearResults: @escaping (UUID) -> Void) -> UUID? {
        guard let idx = lines.firstIndex(where: { $0.id == id }) else { return nil }
        let currentText = lines[idx].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentText.isEmpty, idx > 0 else { return nil }
        
        let prevLineId = lines[idx - 1].id
        let removedLineId = lines[idx].id
        lines.remove(at: idx)
        clearResults(removedLineId)
        return prevLineId
    }
    
    /// Handle newline (Enter key) - splits text on \n and creates new lines
    func handleNewline(
        for id: UUID,
        scheduleParse: @escaping (UUID) -> Void,
        clearResults: @escaping (UUID) -> Void
    ) -> UUID? {
        guard let idx = lines.firstIndex(where: { $0.id == id }),
              idx < lines.count else { return nil }
        let raw = lines[idx].text
        
        // No newline character? Just add new line
        guard raw.contains("\n") else {
            return addLineAndFocus()
        }
        
        // Split on newlines
        let parts = raw.components(separatedBy: CharacterSet.newlines)
        let currentText = parts.first ?? ""
        
        // Re-verify index before mutation
        guard idx < lines.count else { return nil }
        lines[idx].text = currentText
        
        // Clear current line if empty
        let trimmedCurrent = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCurrent.isEmpty {
            guard idx < lines.count else { return nil }
            lines[idx].status = .idle
            clearResults(lines[idx].id)
        }
        
        // Insert new lines for remaining parts
        var insertIndex = idx + 1
        var newIds: [UUID] = []
        for p in parts.dropFirst() {
            let state = LineViewModel(text: p)
            guard insertIndex <= lines.count else { break }
            lines.insert(state, at: insertIndex)
            newIds.append(state.id)
            insertIndex += 1
        }
        
        // Schedule parsing for current line if not empty
        if !trimmedCurrent.isEmpty {
            guard idx < lines.count else { return nil }
            scheduleParse(lines[idx].id)
        }
        
        // Schedule parsing for new lines after a delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            for nid in newIds {
                if let j = lines.firstIndex(where: { $0.id == nid }),
                   j < lines.count {
                    let t = lines[j].text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty {
                        scheduleParse(nid)
                    }
                }
            }
        }
        
        // Return first new line or fallback to current (with safety check)
        if let firstNew = newIds.first {
            return firstNew
        } else if idx < lines.count {
            return lines[idx].id
        } else {
            return nil
        }
    }
}

