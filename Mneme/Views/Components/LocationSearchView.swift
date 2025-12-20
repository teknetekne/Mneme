import SwiftUI
import MapKit

struct LocationSearchView: View {
    @StateObject private var searchService = LocationSearchService()
    @Environment(\.dismiss) private var dismiss
    
    let onLocationSelected: (String, CLLocationCoordinate2D) -> Void
    
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    
                    TextField("Search for a place", text: $searchService.searchQuery)
                        .focused($isSearchFocused)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                    
                    if !searchService.searchQuery.isEmpty {
                        Button {
                            searchService.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding()
                
                // Results
                if searchService.isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchService.searchResults.isEmpty && !searchService.searchQuery.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search")
                    )
                } else if searchService.searchResults.isEmpty {
                    ContentUnavailableView(
                        "Search for Places",
                        systemImage: "map",
                        description: Text("Enter a location name, address, or point of interest")
                    )
                } else {
                    List {
                        ForEach(searchService.searchResults, id: \.self) { result in
                            Button {
                                selectLocation(result)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    
                                    Text(result.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Add Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            isSearchFocused = true
        }
    }
    
    private func selectLocation(_ completion: MKLocalSearchCompletion) {
        Task {
            if let location = await searchService.selectLocation(completion) {
                onLocationSelected(location.name, location.coordinate)
                dismiss()
            }
        }
    }
}


