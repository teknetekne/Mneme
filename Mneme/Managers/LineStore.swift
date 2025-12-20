import Foundation
import Combine
import SwiftUI

// MARK: - Line Store (Dictionary-Based Pattern)

/// Central store for line state and focus
@MainActor
final class LineStore: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Dictionary: UUID → LineViewModel (O(1) access, thread-safe)
    @Published private(set) var linesById: [UUID: LineViewModel] = [:]
    
    /// Display order (array of IDs only)
    @Published private(set) var lineOrder: [UUID] = []
    
    /// Current focused line (view can bind to this)
    @Published var focusedId: UUID?
    
    /// Computed property: ONLY active lines in display order (read-only)
    var lines: [LineViewModel] {
        lineOrder.compactMap { linesById[$0] }.filter { $0.isActive }
    }
    
    // MARK: - Persistence Properties
    
    private let saveDebounceInterval: TimeInterval = 1.0
    private var saveTask: Task<Void, Never>?
    
    // Static flag to track if this is the first load of the app session
    private static var hasSessionStarted = false
    
    private var fileURL: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("notepad_data.json")
    }
    
    // MARK: - Initialization
    
    init(initialLines: [LineViewModel]? = nil) {
        if let initialLines = initialLines, !initialLines.isEmpty {
            for line in initialLines {
                linesById[line.id] = line
                lineOrder.append(line.id)
            }
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let url = documents.appendingPathComponent("notepad_data.json")
            
            // Clear data on fresh launch
            if !Self.hasSessionStarted {
                try? FileManager.default.removeItem(at: url)
                Self.hasSessionStarted = true
            }
            
            // Try to load from disk first
            if let data = try? Data(contentsOf: url),
               let lines = try? JSONDecoder().decode([LineViewModel].self, from: data),
               !lines.isEmpty {
                for line in lines {
                    linesById[line.id] = line
                    lineOrder.append(line.id)
                }
            } else {
                // Fallback to default empty line
                for _ in 0..<50 {
                    let passiveLine = LineViewModel(text: "", isActive: false)
                    linesById[passiveLine.id] = passiveLine
                    lineOrder.append(passiveLine.id)
                }
            }
        }
        
        if let firstId = lineOrder.first {
            if let firstLine = linesById[firstId] {
                firstLine.isActive = true
                self.focusedId = firstId
            }
        }
        
        // Ensure at least one active line if load failed or was empty but had passive lines
        if lines.isEmpty {
            ensureAtLeastOneLine()
        }
    }
    
    // MARK: - Line Updates
    
    func updateText(for id: UUID, newText: String) {
        guard let line = linesById[id] else { return }
        // Modifying the ObservableObject (LineViewModel) directly.
        // This triggers the LineViewModel's publisher, but NOT the LineStore's publisher.
        // This is the key to performance: only the specific LineRowView re-renders.
        if line.text != newText {
            line.text = newText
            scheduleSave()
        }
    }
    
    func updateStatus(for id: UUID, status: ParseStatus) {
        guard let line = linesById[id] else { return }
        if line.status != status {
            objectWillChange.send()
            line.status = status
            scheduleSave()
        }
    }
    
    /// Activate next passive line after given ID (Enter key)
    func activateNextLine(after id: UUID) -> UUID? {
        guard let currentIndex = lineOrder.firstIndex(of: id) else {
            return nil
        }
        let nextIndex = currentIndex + 1
        
        guard nextIndex < lineOrder.count else {
            return nil
        }
        let nextId = lineOrder[nextIndex]
        guard let nextLine = linesById[nextId], !nextLine.isActive else {
            return nil
        }
        
        // Modifying properties doesn't trigger LineStore update, but changing active state
        // might affect the list of *visible* lines if the view filters by isActive.
        // However, since we are just activating an existing line in the dictionary,
        // and the view iterates over lineOrder, we might need to notify if the view filters.
        // But typically the view iterates lineOrder and checks isActive.
        // If the view filters in body, we need to publish.
        // Let's assume we need to publish for structural/visibility changes.
        
        objectWillChange.send()
        
        nextLine.isActive = true
        nextLine.text = ""
        nextLine.status = .idle
        
        focusedId = nextId
        save()
        return nextId
    }

    /// Activate next passive line after the last active line (append-style enter)
    func activateNextLineAtEnd() -> UUID? {
        guard let lastActiveId = lineOrder.reversed().first(where: { linesById[$0]?.isActive == true }) else {
            return nil
        }
        return activateNextLine(after: lastActiveId)
    }
    
    /// Deactivate line (Backspace on empty line)
    func deactivateLine(_ id: UUID) -> UUID? {
        guard let line = linesById[id], line.isActive else { return nil }
        guard let currentIndex = lineOrder.firstIndex(of: id) else { return nil }
        
        let activeCount = lineOrder.compactMap { linesById[$0] }.filter { $0.isActive }.count
        guard activeCount > 1 else { return nil }
        
        var prevIndex = currentIndex - 1
        var focusTarget: UUID?
        while prevIndex >= 0 {
            let prevId = lineOrder[prevIndex]
            if let prevLine = linesById[prevId], prevLine.isActive {
                focusTarget = prevId
                break
            }
            prevIndex -= 1
        }
        
        guard let focusId = focusTarget else { return nil }
        
        objectWillChange.send()
        
        line.isActive = false
        line.text = ""
        line.status = .idle
        
        focusedId = focusId
        save()
        return focusId
    }
    
    // MARK: - Focus helpers
    
    func focus(_ id: UUID?) {
        if let id, let line = linesById[id], line.isActive {
            focusedId = id
        } else {
            if let firstActive = lineOrder.first(where: { linesById[$0]?.isActive == true }) {
                focusedId = firstActive
            }
        }
    }
    
    func focusFirstIfNeeded() {
        if focusedId == nil {
            focusedId = lineOrder.first
        }
    }
    
    // MARK: - Mutation Helpers
    
    /// Add a new empty line after given id (or append at end)
    func addLine(after id: UUID? = nil) -> UUID {
        let newLine = LineViewModel(text: "")
        
        objectWillChange.send()
        
        var newDict = linesById
        var newOrder = lineOrder
        
        newDict[newLine.id] = newLine
        
        if let id, let idx = newOrder.firstIndex(of: id) {
            let insertIndex = idx + 1
            if insertIndex <= newOrder.count {
                newOrder.insert(newLine.id, at: insertIndex)
            } else {
                newOrder.append(newLine.id)
            }
        } else {
            newOrder.append(newLine.id)
        }
        
        linesById = newDict
        lineOrder = newOrder
        focusedId = newLine.id
        
        ensureAtLeastOneLine()
        save()
        return newLine.id
    }
    
    /// Explicit delete; returns focus target
    func deleteLine(_ id: UUID) -> UUID? {
        guard let idx = lineOrder.firstIndex(of: id) else { return nil }
        
        if lineOrder.count == 1 {
            // Last line: reset to empty
            let emptyLine = LineViewModel(text: "")
            objectWillChange.send()
            linesById = [emptyLine.id: emptyLine]
            lineOrder = [emptyLine.id]
            focusedId = emptyLine.id
            save()
            return emptyLine.id
        }
        
        objectWillChange.send()
        
        var newDict = linesById
        var newOrder = lineOrder
        
        newDict.removeValue(forKey: id)
        newOrder.remove(at: idx)
        
        linesById = newDict
        lineOrder = newOrder
        
        if idx > 0 {
            focusedId = newOrder[idx - 1]
        } else {
            focusedId = newOrder.first
        }
        
        ensureAtLeastOneLine()
        save()
        return focusedId
    }
    
    /// Handle backspace on empty line - deletes line and returns previous line ID
    func handleBackspaceOnEmptyLine(for id: UUID) -> UUID? {
        guard let idx = lineOrder.firstIndex(of: id) else { return nil }
        guard let line = linesById[id] else { return nil }
        
        let currentText = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentText.isEmpty, idx > 0 else { return nil }
        
        let prevLineId = lineOrder[idx - 1]
        
        objectWillChange.send()
        
        var newDict = linesById
        var newOrder = lineOrder
        
        newDict.removeValue(forKey: id)
        newOrder.remove(at: idx)
        
        linesById = newDict
        lineOrder = newOrder
        focusedId = prevLineId
        
        ensureAtLeastOneLine()
        save()
        return prevLineId
    }
    
    /// Handle newline (Enter key) - splits text on \n and creates new lines. Returns IDs added (for scheduling) and focus target
    func handleNewline(for id: UUID) -> (focus: UUID?, newLines: [UUID])? {
        guard let idx = lineOrder.firstIndex(of: id) else {
            return nil
        }
        guard let line = linesById[id] else {
            return nil
        }
        let raw = line.text
        
        guard raw.contains("\n") else {
            let newId = addLine(after: id)
            return (focus: newId, newLines: [newId])
        }
        
        let parts = raw.components(separatedBy: CharacterSet.newlines)
        let currentText = parts.first ?? ""
        
        objectWillChange.send()
        
        var newDict = linesById
        var newOrder = lineOrder
        
        line.text = currentText
        // No need to re-assign line to dict since it's a reference type
        
        var insertIndex = idx + 1
        var newIds: [UUID] = []
        for p in parts.dropFirst() {
            let state = LineViewModel(text: p)
            guard insertIndex <= newOrder.count else { break }
            newOrder.insert(state.id, at: insertIndex)
            newDict[state.id] = state
            newIds.append(state.id)
            insertIndex += 1
        }
        
        linesById = newDict
        lineOrder = newOrder
        
        let focusTarget = newIds.first ?? id
        focusedId = focusTarget
        ensureAtLeastOneLine()
        save()
        return (focus: focusTarget, newLines: newIds)
    }
    
    /// Ensure there's always at least one line (prevents empty UI state)
    func ensureAtLeastOneLine() {
        if lineOrder.isEmpty {
            let new = LineViewModel(text: "")
            objectWillChange.send()
            linesById = [new.id: new]
            lineOrder = [new.id]
            focusedId = new.id
            save()
        }
    }
    
    /// Reset store to initial state (first line active & empty, others passive & empty)
    /// This preserves the line objects in memory, avoiding churn.
    func resetToInitialState() {
        objectWillChange.send()
        
        // Clear focus first to ensure UITextView updates
        focusedId = nil
        
        for (index, id) in lineOrder.enumerated() {
            if let line = linesById[id] {
                line.text = ""
                line.status = .idle
                line.isActive = (index == 0) // Only first line active
            }
        }
        
        if let firstId = lineOrder.first {
            focusedId = firstId
        }
        
        save()
    }
    
    // MARK: - Persistence
    
    private func save() {
        let linesToSave = lineOrder.compactMap { linesById[$0] }
        do {
            let data = try JSONEncoder().encode(linesToSave)
            try data.write(to: fileURL)
        } catch {
        }
    }
    
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(saveDebounceInterval * 1_000_000_000))
            if !Task.isCancelled {
                self.save()
            }
        }
    }
}
