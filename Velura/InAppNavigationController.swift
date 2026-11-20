import CoreLocation
import Foundation
import MapKit
import SwiftUI

struct NavigationDestinationItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: NavigationDestinationItem, rhs: NavigationDestinationItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct ActiveRouteGuidance: Equatable {
    let destinationName: String
    let destinationCoordinate: CLLocationCoordinate2D
    let totalDistanceMeters: CLLocationDistance
    let expectedTravelTime: TimeInterval
    let currentInstruction: String
    let nextManeuverSymbol: String
    let distanceToNextManeuverMeters: CLLocationDistance
    let remainingDistanceMeters: CLLocationDistance
    let hasArrived: Bool

    static func == (lhs: ActiveRouteGuidance, rhs: ActiveRouteGuidance) -> Bool {
        lhs.destinationName == rhs.destinationName
            && lhs.totalDistanceMeters == rhs.totalDistanceMeters
            && lhs.expectedTravelTime == rhs.expectedTravelTime
            && lhs.currentInstruction == rhs.currentInstruction
            && lhs.nextManeuverSymbol == rhs.nextManeuverSymbol
            && lhs.distanceToNextManeuverMeters == rhs.distanceToNextManeuverMeters
            && lhs.remainingDistanceMeters == rhs.remainingDistanceMeters
            && lhs.hasArrived == rhs.hasArrived
    }
}

enum NavigationManeuverHelper {
    static func symbol(for instruction: String) -> String {
        let lower = instruction.lowercased()
        if lower.contains("u-turn") || lower.contains("wenden") {
            return "arrow.uturn.left"
        }
        if lower.contains("roundabout") || lower.contains("kreisverkehr") {
            return "arrow.triangle.2.circlepath"
        }
        if lower.contains("sharp left") || lower.contains("scharf links") {
            return "arrow.turn.up.left"
        }
        if lower.contains("sharp right") || lower.contains("scharf rechts") {
            return "arrow.turn.up.right"
        }
        if lower.contains("slight left") || lower.contains("leicht links") || lower.contains("keep left") {
            return "arrow.up.left"
        }
        if lower.contains("slight right") || lower.contains("leicht rechts") || lower.contains("keep right") {
            return "arrow.up.right"
        }
        if lower.contains("left") || lower.contains("links") {
            return "arrow.turn.up.left"
        }
        if lower.contains("right") || lower.contains("rechts") {
            return "arrow.turn.up.right"
        }
        if lower.contains("merge") || lower.contains("einfädeln") {
            return "arrow.merge"
        }
        if lower.contains("arrive") || lower.contains("destination") || lower.contains("ziel") {
            return "flag.checkered"
        }
        return "arrow.up"
    }

    static func formattedDistance(_ meters: CLLocationDistance, usesMiles: Bool) -> String {
        let clamped = max(0, meters)
        if usesMiles {
            let miles = clamped / 1_609.344
            if miles >= 0.2 {
                return String(format: "%.1f mi", miles)
            }
            let feet = Int((clamped * 3.28084 / 50).rounded()) * 50
            return "\(max(50, feet)) ft"
        } else {
            if clamped >= 1_000 {
                return String(format: "%.1f km", clamped / 1_000)
            }
            let rounded = Int((clamped / 10).rounded()) * 10
            return "\(max(10, rounded)) m"
        }
    }

    static func formattedETA(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        let hours = minutes / 60
        let rem = minutes % 60
        if hours > 0 {
            return "\(hours)h \(rem)m"
        }
        return "\(minutes) min"
    }
}

@MainActor
final class InAppNavigationController: ObservableObject {
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [NavigationDestinationItem] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isCalculatingRoute = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var activeRoute: MKRoute?
    @Published private(set) var guidance: ActiveRouteGuidance?

    private var activeSteps: [MKRoute.Step] = []
    private var currentStepIndex = 0
    private var destinationName = ""
    private var destinationCoordinate: CLLocationCoordinate2D?

    var routeCoordinates: [CLLocationCoordinate2D] {
        guard let polyline = activeRoute?.polyline else { return [] }
        var coords = Array(repeating: kCLLocationCoordinate2DInvalid, count: polyline.pointCount)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: polyline.pointCount))
        return coords.filter(CLLocationCoordinate2DIsValid)
    }

    func search(near coordinate: CLLocationCoordinate2D?) {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            errorMessage = nil
            return
        }

        isSearching = true
        errorMessage = nil

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        if let coordinate, CLLocationCoordinate2DIsValid(coordinate) {
            request.region = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 60_000,
                longitudinalMeters: 60_000
            )
        }

        let search = MKLocalSearch(request: request)
        Task { [weak self] in
            do {
                let response = try await search.start()
                guard let self else { return }
                self.isSearching = false
                self.searchResults = response.mapItems.compactMap { item in
                    let coord = item.placemark.coordinate
                    guard CLLocationCoordinate2DIsValid(coord) else { return nil }
                    let title = item.name ?? item.placemark.title ?? trimmed
                    let subtitle = item.placemark.title ?? ""
                    return NavigationDestinationItem(name: title, subtitle: subtitle, coordinate: coord)
                }
                if self.searchResults.isEmpty {
                    self.errorMessage = "No places found for \"\(trimmed)\"."
                }
            } catch {
                guard let self else { return }
                self.isSearching = false
                self.errorMessage = "Search failed. Check your connection and try again."
            }
        }
    }

    func startNavigation(to destination: NavigationDestinationItem, from origin: CLLocationCoordinate2D?) {
        isCalculatingRoute = true
        errorMessage = nil

        let request = MKDirections.Request()
        if let origin, CLLocationCoordinate2DIsValid(origin) {
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin))
        } else {
            request.source = MKMapItem.forCurrentLocation()
        }
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        Task { [weak self] in
            do {
                let response = try await directions.calculate()
                guard let self else { return }
                self.isCalculatingRoute = false
                guard let route = response.routes.first else {
                    self.errorMessage = "No driving route found to \(destination.name)."
                    return
                }
                self.activeRoute = route
                self.destinationName = destination.name
                self.destinationCoordinate = destination.coordinate
                self.activeSteps = route.steps.filter { !$0.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                self.currentStepIndex = 0
                self.updateGuidance(userCoordinate: origin)
            } catch {
                guard let self else { return }
                self.isCalculatingRoute = false
                self.errorMessage = "Could not calculate route. Make sure location access is enabled."
            }
        }
    }

    func updateGuidance(userCoordinate: CLLocationCoordinate2D?) {
        guard let route = activeRoute, let destCoord = destinationCoordinate else { return }

        let destLocation = CLLocation(latitude: destCoord.latitude, longitude: destCoord.longitude)
        let userLocation = userCoordinate.flatMap {
            CLLocationCoordinate2DIsValid($0) ? CLLocation(latitude: $0.latitude, longitude: $0.longitude) : nil
        }

        if let userLocation, userLocation.distance(from: destLocation) <= 45 {
            guidance = ActiveRouteGuidance(
                destinationName: destinationName,
                destinationCoordinate: destCoord,
                totalDistanceMeters: route.distance,
                expectedTravelTime: 0,
                currentInstruction: "Arrived at \(destinationName)",
                nextManeuverSymbol: "flag.checkered",
                distanceToNextManeuverMeters: 0,
                remainingDistanceMeters: 0,
                hasArrived: true
            )
            return
        }

        if let userLocation, !activeSteps.isEmpty {
            // Advance step if the user is close to the end of the current step's polyline.
            while currentStepIndex < activeSteps.count - 1 {
                let step = activeSteps[currentStepIndex]
                if let endCoord = lastCoordinate(of: step.polyline) {
                    let endLoc = CLLocation(latitude: endCoord.latitude, longitude: endCoord.longitude)
                    if userLocation.distance(from: endLoc) <= 35 {
                        currentStepIndex += 1
                        continue
                    }
                }
                break
            }
        }

        let currentStep = activeSteps.indices.contains(currentStepIndex) ? activeSteps[currentStepIndex] : nil
        let instruction = currentStep?.instructions ?? "Follow route to \(destinationName)"
        let maneuverDistance: CLLocationDistance
        if let userLocation, let step = currentStep, let endCoord = lastCoordinate(of: step.polyline) {
            maneuverDistance = userLocation.distance(from: CLLocation(latitude: endCoord.latitude, longitude: endCoord.longitude))
        } else {
            maneuverDistance = currentStep?.distance ?? route.distance
        }

        let remainingDistance: CLLocationDistance
        if let userLocation {
            let directRemaining = userLocation.distance(from: destLocation)
            let stepsRemaining = activeSteps.dropFirst(currentStepIndex).reduce(0.0) { $0 + $1.distance }
            remainingDistance = max(directRemaining, min(route.distance, stepsRemaining))
        } else {
            remainingDistance = route.distance
        }

        let ratio = route.distance > 0 ? min(1, remainingDistance / route.distance) : 0
        guidance = ActiveRouteGuidance(
            destinationName: destinationName,
            destinationCoordinate: destCoord,
            totalDistanceMeters: route.distance,
            expectedTravelTime: route.expectedTravelTime * ratio,
            currentInstruction: instruction,
            nextManeuverSymbol: NavigationManeuverHelper.symbol(for: instruction),
            distanceToNextManeuverMeters: maneuverDistance,
            remainingDistanceMeters: remainingDistance,
            hasArrived: false
        )
    }

    func stopNavigation() {
        activeRoute = nil
        guidance = nil
        activeSteps = []
        currentStepIndex = 0
        destinationName = ""
        destinationCoordinate = nil
    }

    private func lastCoordinate(of polyline: MKPolyline) -> CLLocationCoordinate2D? {
        guard polyline.pointCount > 0 else { return nil }
        var coord = kCLLocationCoordinate2DInvalid
        polyline.getCoordinates(&coord, range: NSRange(location: polyline.pointCount - 1, length: 1))
        return CLLocationCoordinate2DIsValid(coord) ? coord : nil
    }
}
