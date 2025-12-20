import Foundation

// MARK: - Calorie Source

struct CalorieSource: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let url: String?
    let calories: Double?
    let logoName: String?
    
    init(name: String, url: String? = nil, calories: Double? = nil, logoName: String? = nil) {
        self.id = UUID()
        self.name = name
        self.url = url
        self.calories = calories
        self.logoName = logoName
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, url, calories, logoName
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        calories = try container.decodeIfPresent(Double.self, forKey: .calories)
        logoName = try container.decodeIfPresent(String.self, forKey: .logoName)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(calories, forKey: .calories)
        try container.encodeIfPresent(logoName, forKey: .logoName)
    }
}
