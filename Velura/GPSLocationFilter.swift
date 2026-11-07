import CoreLocation
import Foundation

enum GPSLocationIssue: Equatable {
    case stale
    case inaccurate
    case implausible

    var title: String {
        switch self {
        case .stale: "GPS STALE"
        case .inaccurate, .implausible: "GPS UNRELIABLE"
        }
    }

    var detail: String {
        switch self {
        case .stale: "Ignoring an outdated location sample"
        case .inaccurate: "Poor GPS accuracy · waiting for a better fix"
        case .implausible: "Ignoring an implausible GPS sample"
        }
    }
}

struct GPSLocationFilter {
    private let maximumSampleAge: TimeInterval = 5
    private let maximumHorizontalAccuracy: CLLocationAccuracy = 35
    private let maximumSpeedAccuracy: Double = 15
    private let maximumPlausibleSpeedKmh = 360.0
    private let maximumPlausibleSpeedMetersPerSecond = 100.0
    private let maximumPositionErrorAllowance: CLLocationDistance = 40
    private let minimumPositionErrorAllowance: CLLocationDistance = 10

    func issue(
        for location: CLLocation,
        receivedAt: Date,
        previousLocation: CLLocation?
    ) -> GPSLocationIssue? {
        let age = receivedAt.timeIntervalSince(location.timestamp)
        guard age.isFinite, age >= -1, age <= maximumSampleAge else { return .stale }

        guard CLLocationCoordinate2DIsValid(location.coordinate),
              location.horizontalAccuracy.isFinite,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maximumHorizontalAccuracy else {
            return .inaccurate
        }

        guard location.speed.isFinite, location.speed >= 0 else { return .inaccurate }
        guard location.speed * 3.6 <= maximumPlausibleSpeedKmh else { return .implausible }
        guard location.speedAccuracy.isFinite else { return .inaccurate }
        if location.speedAccuracy >= 0 && location.speedAccuracy > maximumSpeedAccuracy {
            return .inaccurate
        }

        guard let previousLocation else { return nil }
        let timeDelta = location.timestamp.timeIntervalSince(previousLocation.timestamp)
        guard timeDelta > 0 else { return .stale }
        guard timeDelta <= maximumSampleAge else { return nil }

        let distance = location.distance(from: previousLocation)
        guard distance.isFinite else { return .inaccurate }
        let positionErrorAllowance = min(
            maximumPositionErrorAllowance,
            max(minimumPositionErrorAllowance, previousLocation.horizontalAccuracy + location.horizontalAccuracy)
        )
        let maximumPlausibleDistance = maximumPlausibleSpeedMetersPerSecond * timeDelta + positionErrorAllowance
        guard distance <= maximumPlausibleDistance else { return .implausible }

        let impliedSpeed = distance / timeDelta
        let speedMismatchAllowance = min(
            35,
            max(15, positionErrorAllowance / max(timeDelta, 1))
        )
        guard abs(location.speed - impliedSpeed) <= speedMismatchAllowance else { return .implausible }

        return nil
    }
}
