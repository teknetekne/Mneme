import FoundationModels

protocol LanguageModelAvailabilityProviding {
    var isAvailable: Bool { get }
}

struct SystemLanguageModelAvailabilityProvider: LanguageModelAvailabilityProviding {
    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }
}

struct FixedLanguageModelAvailabilityProvider: LanguageModelAvailabilityProviding {
    let isAvailable: Bool
}
