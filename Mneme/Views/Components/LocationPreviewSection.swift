import SwiftUI
import MapKit
import CoreLocation

struct TravelEstimate: Identifiable, Equatable {
    let id = UUID()
    let mode: String
    let symbol: String
    let distanceText: String
    let durationText: String
}

struct LocationPreviewSection: View {
    let locationName: String
    
    @State private var destinationCoordinate: CLLocationCoordinate2D?
    @State private var walkingEstimate: TravelEstimate?
    @State private var drivingEstimate: TravelEstimate?
    @State private var publicTransportEstimate: TravelEstimate?
    @State private var isGeocoding = false
    @State private var geocodeError: String?
    @State private var hasLoadedRoutes = false
    @State private var hasUpdatedRoutes = false
    @State private var routeTask: Task<Void, Never>?
    @State private var geocodeTask: Task<Void, Never>?
    
    @StateObject private var locationProvider = LocationProvider()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Location")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(locationName)
                .font(.headline)
            
            if let coordinate = destinationCoordinate {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))) {
                    Marker(locationName, coordinate: coordinate)
                        .tint(Color.accentColor)
                }
                .mapStyle(.standard)
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if isGeocoding {
                ProgressView("Finding location…")
            } else if let geocodeError = geocodeError {
                Text(geocodeError)
                    .foregroundStyle(.secondary)
            }
            
            if locationProvider.authorizationStatus == .denied || locationProvider.authorizationStatus == .restricted {
                HStack {
                    Image(systemName: "location.slash")
                        .foregroundStyle(.secondary)
                    Text("Location access needed for travel estimates")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                travelRow(mode: "Walking", symbol: "figure.walk", estimate: walkingEstimate)
                travelRow(mode: "Driving", symbol: "car", estimate: drivingEstimate)
                travelRow(mode: "Public Transport", symbol: "tram.fill", estimate: publicTransportEstimate)
            }
        }
        .onAppear {
            if !hasLoadedRoutes {
                hasLoadedRoutes = true
                hasUpdatedRoutes = false
                locationProvider.requestAccess()
                geocodeLocation()
            }
        }
        .onDisappear {
            routeTask?.cancel()
            routeTask = nil
            geocodeTask?.cancel()
            geocodeTask = nil
        }
        .onChange(of: locationProvider.currentLocation) { _, newLocation in
            if hasLoadedRoutes && !hasUpdatedRoutes, let _ = newLocation, let _ = destinationCoordinate {
                hasUpdatedRoutes = true
                updateRoutes()
            }
        }
    }
    
    private func travelRow(mode: String, symbol: String, estimate: TravelEstimate?) -> some View {
        HStack {
            Label(mode, systemImage: symbol)
            Spacer()
            if let estimate = estimate {
                Text("\(estimate.durationText) • \(estimate.distanceText)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("No directions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func geocodeLocation() {
        guard !locationName.isEmpty else { return }
        geocodeTask?.cancel()
        isGeocoding = true
        geocodeError = nil
        
        geocodeTask = Task {
            do {
                if #available(iOS 26.0, *) {
                    guard let request = MKGeocodingRequest(addressString: locationName) else {
                        await MainActor.run {
                            self.isGeocoding = false
                            self.geocodeError = "Could not determine location."
                        }
                        return
                    }
                    
                    let mapItems = try await request.mapItems
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        self.isGeocoding = false
                        if #available(iOS 26.0, *) {
                            if let mapItem = mapItems.first {
                                self.destinationCoordinate = mapItem.location.coordinate
                                if let _ = self.locationProvider.currentLocation {
                                    self.hasUpdatedRoutes = true
                                    self.updateRoutes()
                                }
                            } else {
                                self.geocodeError = "Could not determine location."
                            }
                        } else {
                            if let coordinate = mapItems.first?.placemark.location?.coordinate {
                                self.destinationCoordinate = coordinate
                                if let _ = self.locationProvider.currentLocation {
                                    self.hasUpdatedRoutes = true
                                    self.updateRoutes()
                                }
                            } else {
                                self.geocodeError = "Could not determine location."
                            }
                        }
                    }
                } else {
                    let geocoder = CLGeocoder()
                    let placemarks = try await geocoder.geocodeAddressString(locationName)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        self.isGeocoding = false
                        if let coordinate = placemarks.first?.location?.coordinate {
                            self.destinationCoordinate = coordinate
                            if let _ = self.locationProvider.currentLocation {
                                self.hasUpdatedRoutes = true
                                self.updateRoutes()
                            }
                        } else {
                            self.geocodeError = "Could not determine location."
                        }
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.isGeocoding = false
                    self.geocodeError = error.localizedDescription
                }
            }
        }
    }
    
    private func updateRoutes() {
        guard let destination = destinationCoordinate,
              let origin = locationProvider.currentLocation else {
            walkingEstimate = nil
            drivingEstimate = nil
            publicTransportEstimate = nil
            return
        }
        
        routeTask?.cancel()
        routeTask = Task {
            walkingEstimate = await calculateRoute(
                from: origin,
                to: destination,
                transport: .walking,
                mode: "Walking",
                symbol: "figure.walk"
            )
            guard !Task.isCancelled else { return }
            drivingEstimate = await calculateRoute(
                from: origin,
                to: destination,
                transport: .automobile,
                mode: "Driving",
                symbol: "car"
            )
            guard !Task.isCancelled else { return }
            publicTransportEstimate = await calculateRoute(
                from: origin,
                to: destination,
                transport: .transit,
                mode: "Public Transport",
                symbol: "tram.fill"
            )
        }
    }
    
    private func calculateRoute(
        from origin: CLLocation,
        to destination: CLLocationCoordinate2D,
        transport: MKDirectionsTransportType,
        mode: String,
        symbol: String
    ) async -> TravelEstimate? {
        guard !Task.isCancelled else { return nil }
        
        let request = MKDirections.Request()
        
        if #available(iOS 26.0, *) {
            request.source = MKMapItem(location: origin, address: nil)
            request.destination = MKMapItem(location: CLLocation(latitude: destination.latitude, longitude: destination.longitude), address: nil)
        } else {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        }
        
        request.transportType = transport
        
        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            guard !Task.isCancelled else { return nil }
            guard let route = response.routes.first else { return nil }
            let distanceText = format(distance: route.distance)
            let durationText = format(duration: route.expectedTravelTime)
            return TravelEstimate(mode: mode, symbol: symbol, distanceText: distanceText, durationText: durationText)
        } catch {
            return nil
        }
    }
    
    private func format(distance: CLLocationDistance) -> String {
        let measurement = Measurement(value: distance, unit: UnitLength.meters)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: measurement)
    }
    
    private func format(duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remaining = minutes % 60
            return "\(hours) h \(remaining) min"
        }
    }
}
