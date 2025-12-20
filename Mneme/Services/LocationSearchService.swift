import Foundation
import MapKit
import Combine

@MainActor
class LocationSearchService: NSObject, ObservableObject {
    @Published var searchQuery = ""
    @Published var searchResults: [MKLocalSearchCompletion] = []
    @Published var isSearching = false
    
    private let completer: MKLocalSearchCompleter
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        self.completer = MKLocalSearchCompleter()
        super.init()
        
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        
        // Debounce search query
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] query in
                self?.performSearch(query: query)
            }
            .store(in: &cancellables)
    }
    
    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = []
            isSearching = false
            return
        }
        
        isSearching = true
        completer.queryFragment = query
    }
    
    func selectLocation(_ completion: MKLocalSearchCompletion) async -> (name: String, coordinate: CLLocationCoordinate2D)? {
        let searchRequest = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: searchRequest)
        
        do {
            let response = try await search.start()
            guard let mapItem = response.mapItems.first else { return nil }
            
            let name = mapItem.name ?? completion.title
            if #available(iOS 26.0, *) {
                return (name: name, coordinate: mapItem.location.coordinate)
            } else {
                guard let coordinate = mapItem.placemark.location?.coordinate else { return nil }
                return (name: name, coordinate: coordinate)
            }
        } catch {
            return nil
        }
    }
    
    func reset() {
        searchQuery = ""
        searchResults = []
        isSearching = false
    }
}

extension LocationSearchService: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor in
            self.searchResults = completer.results
            self.isSearching = false
        }
    }
    
    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.searchResults = []
            self.isSearching = false
        }
    }
}


