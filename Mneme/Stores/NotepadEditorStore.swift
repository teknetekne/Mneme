import Foundation
import Combine

/// Lightweight, single-source-of-truth store for notepad editing.
/// Holds lines, focus and parse status; reducer driven.
final class NotepadEditorStore: ObservableObject {
    
    // MARK: - Inner Types
    
    struct Line: Identifiable, Equatable {
        let id: UUID
        var text: String
        var status: ParseStatus
        
        init(id: UUID = UUID(), text: String = "", status: ParseStatus = .idle) {
            self.id = id
            self.text = text
            self.status = status
        }
    }
    
    struct State {
        var lines: [Line]
        var focusedId: UUID?
        
        init(lines: [Line] = [Line()]) {
            let seed = lines.isEmpty ? [Line()] : lines
            self.lines = seed
            self.focusedId = seed.first?.id
        }
        
        mutating func ensureAtLeastOneLine() {
            if lines.isEmpty {
                let line = Line()
                lines = [line]
                focusedId = line.id
            }
        }
    }
    
    enum Action {
        case textChanged(id: UUID, text: String)
        case submit(id: UUID)
        case delete(id: UUID)
        case focus(id: UUID?)
        case setStatus(id: UUID, status: ParseStatus)
    }
    
    // MARK: - Published State
    
    @Published private(set) var state: State
    
    init(initialState: State = State()) {
        self.state = initialState
    }
    
    // MARK: - Dispatch
    
    func dispatch(_ action: Action) {
        reduce(state: &state, action: action)
    }
    
    // MARK: - Reducer
    
    private func reduce(state: inout State, action: Action) {
        switch action {
        case .textChanged(let id, let text):
            guard let idx = state.lines.firstIndex(where: { $0.id == id }) else { return }
            state.lines[idx].text = text
            state.lines[idx].status = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .idle : state.lines[idx].status
            
        case .submit(let id):
            guard let idx = state.lines.firstIndex(where: { $0.id == id }) else { return }
            let newLine = Line()
            state.lines.insert(newLine, at: idx + 1)
            state.focusedId = newLine.id
            
        case .delete(let id):
            guard let idx = state.lines.firstIndex(where: { $0.id == id }) else { return }
            if state.lines.count == 1 {
                // Clear last line instead of removing
                state.lines[0].text = ""
                state.lines[0].status = .idle
                state.focusedId = state.lines[0].id
            } else {
                state.lines.remove(at: idx)
                let focusIdx = max(0, idx - 1)
                state.focusedId = state.lines[focusIdx].id
            }
            state.ensureAtLeastOneLine()
            
        case .focus(let id):
            if let id, state.lines.contains(where: { $0.id == id }) {
                state.focusedId = id
            } else {
                state.focusedId = state.lines.first?.id
            }
            
        case .setStatus(let id, let status):
            guard let idx = state.lines.firstIndex(where: { $0.id == id }) else { return }
            state.lines[idx].status = status
        }
    }
}
