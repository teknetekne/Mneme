import Foundation
import CoreLocation
import Combine

// MARK: - Location Manager

/// Manages location and URL operations for notepad lines
/// Responsibility: Location search, current location, URL parsing
@MainActor
final class LocationManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Location names keyed by line UUID
    @Published private(set) var lineLocationNames: [UUID: String] = [:]
    
    /// URLs keyed by line UUID
    @Published private(set) var lineURLs: [UUID: URL] = [:]
    
    // MARK: - Dependencies
    
    private let locationProvider: LocationProvider
    private let locationSearchService: LocationSearchService
    
    // MARK: - Initialization
    
    init(
        locationProvider: LocationProvider? = nil,
        locationSearchService: LocationSearchService? = nil
    ) {
        self.locationProvider = locationProvider ?? LocationProvider()
        self.locationSearchService = locationSearchService ?? LocationSearchService()
    }
    
    // MARK: - Location Operations
    
    /// Set location for a line
    /// - Parameters:
    ///   - lineId: UUID of the line
    ///   - locationName: Name of the location
    func setLocation(for lineId: UUID, locationName: String) {
        lineLocationNames[lineId] = locationName
    }
    
    /// Get location for a line
    /// - Parameter lineId: UUID of the line
    /// - Returns: Location name or nil
    func getLocation(for lineId: UUID) -> String? {
        lineLocationNames[lineId]
    }
    
    /// Remove location from a line
    /// - Parameter lineId: UUID of the line
    func removeLocation(from lineId: UUID) {
        lineLocationNames.removeValue(forKey: lineId)
    }
    
    /// Get current device location
    /// - Returns: Current CLLocation or nil
    func getCurrentLocation() -> CLLocation? {
        locationProvider.currentLocation
    }
    
    /// Request location authorization
    func requestLocationAuthorization() {
        locationProvider.requestAccess()
    }
    
    // MARK: - URL Operations
    
    /// Set URL for a line
    /// - Parameters:
    ///   - lineId: UUID of the line
    ///   - url: URL to associate
    func setURL(for lineId: UUID, url: URL) {
        lineURLs[lineId] = url
    }
    
    /// Get URL for a line
    /// - Parameter lineId: UUID of the line
    /// - Returns: URL or nil
    func getURL(for lineId: UUID) -> URL? {
        lineURLs[lineId]
    }
    
    /// Remove URL from a line
    /// - Parameter lineId: UUID of the line
    func removeURL(from lineId: UUID) {
        lineURLs.removeValue(forKey: lineId)
    }
    
    /// Parse URL from text
    /// - Parameter text: Text to parse
    /// - Returns: URL if found, nil otherwise
    func parseURL(from text: String) -> URL? {
        // Try to detect URLs in text
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        guard let detector = detector else { return nil }
        
        let matches = detector.matches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: text.utf16.count)
        )
        
        return matches.first?.url
    }
    
    /// Detect and store URL from text for a line
    /// - Parameters:
    ///   - text: Text to search for URLs
    ///   - lineId: UUID of the line
    func detectAndStoreURL(in text: String, for lineId: UUID) {
        let pattern = "(https?://[^\\s]+|www\\.[^\\s]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return
        }
        
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex.firstMatch(in: text, range: range),
           let urlRange = Range(match.range, in: text) {
            var urlString = String(text[urlRange])
            
            if urlString.hasPrefix("www.") {
                urlString = "https://" + urlString
            }
            
            if let url = URL(string: urlString) {
                lineURLs[lineId] = url
            }
        } else {
            lineURLs.removeValue(forKey: lineId)
        }
    }
    
    // MARK: - Cleanup
    
    /// Clear location and URL for a line
    /// - Parameter lineId: UUID of the line
    func clearAll(for lineId: UUID) {
        removeLocation(from: lineId)
        removeURL(from: lineId)
    }
    
    /// Clear all locations and URLs
    func clearAllData() {
        lineLocationNames.removeAll()
        lineURLs.removeAll()
    }
}
