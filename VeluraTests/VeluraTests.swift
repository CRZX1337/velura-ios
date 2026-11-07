import CoreLocation
import Testing
@testable import Velura

struct VeluraTests {
    private let filter = GPSLocationFilter()

    @Test func rejectsStaleLocationSamples() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let sample = location(latitude: 37, longitude: -122, accuracy: 5, speed: 0, at: timestamp)

        #expect(filter.issue(for: sample, receivedAt: timestamp.addingTimeInterval(6), previousLocation: nil) == .stale)
    }

    @Test func rejectsInaccurateLocationSamples() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let sample = location(latitude: 37, longitude: -122, accuracy: 40, speed: 0, at: timestamp)

        #expect(filter.issue(for: sample, receivedAt: timestamp, previousLocation: nil) == .inaccurate)
    }

    @Test func rejectsImplausibleReportedSpeed() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let sample = location(latitude: 37, longitude: -122, accuracy: 5, speed: 101, at: timestamp)

        #expect(filter.issue(for: sample, receivedAt: timestamp, previousLocation: nil) == .implausible)
    }

    @Test func rejectsImplausiblePositionJump() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let previous = location(latitude: 37, longitude: -122, accuracy: 5, speed: 0, at: timestamp)
        let sample = location(latitude: 37, longitude: -121.99, accuracy: 5, speed: 0, at: timestamp.addingTimeInterval(1))

        #expect(filter.issue(for: sample, receivedAt: sample.timestamp, previousLocation: previous) == .implausible)
    }

    @Test func acceptsNextPlausibleLocationAfterAnOutlier() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let previous = location(latitude: 37, longitude: -122, accuracy: 5, speed: 5, at: timestamp)
        let sample = location(latitude: 37, longitude: -121.9999, accuracy: 5, speed: 5, at: timestamp.addingTimeInterval(2))

        #expect(filter.issue(for: sample, receivedAt: sample.timestamp, previousLocation: previous) == nil)
    }

    private func location(
        latitude: CLLocationDegrees,
        longitude: CLLocationDegrees,
        accuracy: CLLocationAccuracy,
        speed: CLLocationSpeed,
        at timestamp: Date
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: 0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 10,
            course: 0,
            speed: speed,
            timestamp: timestamp
        )
    }
}
