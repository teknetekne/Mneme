import Foundation
import Combine
import SwiftUI

// MARK: - Line State

/// Represents the state of a single notepad line
// MARK: - Line ViewModel

/// Represents the state of a single notepad line (Observable for granular updates)
final class LineViewModel: ObservableObject, Identifiable, Equatable, Codable {
    let id: UUID
    @Published var text: String
    @Published var status: ParseStatus
    @Published var isActive: Bool
    
    enum CodingKeys: String, CodingKey {
        case id, text, status, isActive
    }
    
    init(id: UUID = UUID(), text: String, status: ParseStatus = .idle, isActive: Bool = true) {
        self.id = id
        self.text = text
        self.status = status
        self.isActive = isActive
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        status = try container.decode(ParseStatus.self, forKey: .status)
        isActive = try container.decode(Bool.self, forKey: .isActive)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(status, forKey: .status)
        try container.encode(isActive, forKey: .isActive)
    }
    
    static func == (lhs: LineViewModel, rhs: LineViewModel) -> Bool {
        lhs.id == rhs.id &&
        lhs.text == rhs.text &&
        lhs.status == rhs.status &&
        lhs.isActive == rhs.isActive
    }
}

// MARK: - Parse Status

/// Represents the parsing status of a line
enum ParseStatus: Equatable, Codable {
    case idle
    case loading
    case success
    case error
}

// MARK: - Parsing Result Item

struct ParsingResultItem: Identifiable {
    let id = UUID()
    let field: String
    let value: String
    let isValid: Bool
    let errorMessage: String?
    let rawValue: String?
    let confidence: Double?

    init(field: String, value: String, isValid: Bool, errorMessage: String? = nil, rawValue: String? = nil, confidence: Double? = nil) {
        self.field = field
        self.value = value
        self.isValid = isValid
        self.errorMessage = errorMessage
        self.rawValue = rawValue
        self.confidence = confidence
    }
}




