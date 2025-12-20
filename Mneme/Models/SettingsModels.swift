import Foundation
import SwiftUI
import HealthKit

enum BiologicalSex: String, Codable, CaseIterable, Sendable {
    case notSet = "notSet"
    case female = "female"
    case male = "male"
    case other = "other"
    
    var displayName: String {
        switch self {
        case .notSet: return "Not Set"
        case .female: return "Female"
        case .male: return "Male"
        case .other: return "Other"
        }
    }
    
    init(from hkSex: HKBiologicalSex) {
        switch hkSex {
        case .notSet: self = .notSet
        case .female: self = .female
        case .male: self = .male
        case .other: self = .other
        @unknown default: self = .notSet
        }
    }
}

enum UnitSystem: String, Codable, CaseIterable, Sendable {
    case metric = "metric"
    case imperial = "imperial"
    
    var displayName: String {
        switch self {
        case .metric: return "Metric"
        case .imperial: return "Imperial"
        }
    }
}

enum TimeFormat: String, Codable, CaseIterable, Sendable {
    case twelveHour = "12h"
    case twentyFourHour = "24h"
    
    var displayName: String {
        switch self {
        case .twelveHour: return "12-Hour"
        case .twentyFourHour: return "24-Hour"
        }
    }
}

enum AppDateFormat: String, Codable, CaseIterable, Sendable {
    case systemDefault = "default"
    case yyyyMMdd = "yyyy-MM-dd"
    case ddMMyyyy = "dd-MM-yyyy"
    case mmDDyyyy = "MM-dd-yyyy"
    
    nonisolated var displayName: String {
        switch self {
        case .systemDefault: return "System Default"
        case .yyyyMMdd: return "YYYY-MM-DD"
        case .ddMMyyyy: return "DD-MM-YYYY"
        case .mmDDyyyy: return "MM-DD-YYYY"
        }
    }
    
    nonisolated var formatString: String? {
        switch self {
        case .systemDefault: return nil
        case .yyyyMMdd: return "yyyy-MM-dd"
        case .ddMMyyyy: return "dd-MM-yyyy"
        case .mmDDyyyy: return "MM-dd-yyyy"
        }
    }
}

enum AppTheme: String, Codable, CaseIterable, Sendable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
