import CoreLocation
import Foundation
import SwiftUI

enum RouteSpeedBand: String, CaseIterable, Identifiable, Equatable {
    case slow
    case moderate
    case fast

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slow: "Slow"
        case .moderate: "Medium"
        case .fast: "Fast"
        }
    }

    func rangeLabel(usesMiles: Bool) -> String {
        if usesMiles {
            switch self {
            case .slow: "< 30 mph"
            case .moderate: "30–55 mph"
            case .fast: "55+ mph"
            }
        } else {
            switch self {
            case .slow: "< 50 km/h"
            case .moderate: "50–90 km/h"
            case .fast: "90+ km/h"
            }
        }
    }

    var color: Color {
        switch self {
        case .slow: Color(red: 0.22, green: 0.78, blue: 0.74)
        case .moderate: Color(red: 0.98, green: 0.71, blue: 0.22)
        case .fast: Color(red: 0.98, green: 0.31, blue: 0.29)
        }
    }

    static func classify(speedKmh: Double) -> RouteSpeedBand? {
        guard speedKmh.isFinite, speedKmh >= 0, speedKmh <= 360 else { return nil }
        if speedKmh < 50 { return .slow }
        if speedKmh < 90 { return .moderate }
        return .fast
    }
}

struct RouteHeatmapSegment: Identifiable, Equatable {
    let id: Int
    let band: RouteSpeedBand
    let coordinates: [CLLocationCoordinate2D]

    static func == (lhs: RouteHeatmapSegment, rhs: RouteHeatmapSegment) -> Bool {
        guard lhs.id == rhs.id, lhs.band == rhs.band, lhs.coordinates.count == rhs.coordinates.count else {
            return false
        }
        return zip(lhs.coordinates, rhs.coordinates).allSatisfy {
            $0.latitude == $1.latitude && $0.longitude == $1.longitude
        }
    }
}

enum RouteSpeedHeatmapBuilder {
    static let maximumPointsPerRoute = 1_200

    static func hasSpeedData(in points: [DriveRoutePoint]) -> Bool {
        points.contains { point in
            guard let speed = point.speedKmh else { return false }
            return RouteSpeedBand.classify(speedKmh: speed) != nil
        }
    }

    /// Builds contiguous MapKit polyline chunks grouped by speed band without bridging gaps or
    /// inventing speed values for historical points that have `speedKmh == nil`.
    static func buildSegments(
        from points: [DriveRoutePoint],
        maxPoints: Int = maximumPointsPerRoute
    ) -> [RouteHeatmapSegment] {
        let validPoints = points.filter {
            $0.latitude.isFinite && $0.longitude.isFinite
                && (-90.0...90.0).contains($0.latitude)
                && (-180.0...180.0).contains($0.longitude)
        }
        guard validPoints.count >= 2 else { return [] }

        let sampled = downsampleIfNeeded(validPoints, limit: maxPoints)
        var result: [RouteHeatmapSegment] = []
        var currentBand: RouteSpeedBand?
        var currentCoords: [CLLocationCoordinate2D] = []
        var nextID = 0

        func flushCurrent() {
            if let band = currentBand, currentCoords.count >= 2 {
                result.append(RouteHeatmapSegment(id: nextID, band: band, coordinates: currentCoords))
                nextID += 1
            }
            currentBand = nil
            currentCoords.removeAll(keepingCapacity: true)
        }

        for index in 0..<(sampled.count - 1) {
            let start = sampled[index]
            let end = sampled[index + 1]

            guard start.segmentIndex == end.segmentIndex else {
                flushCurrent()
                continue
            }

            let pairSpeed: Double?
            switch (start.speedKmh, end.speedKmh) {
            case let (s1?, s2?) where s1.isFinite && s2.isFinite && s1 >= 0 && s2 >= 0 && s1 <= 360 && s2 <= 360:
                pairSpeed = (s1 + s2) / 2
            case let (s1?, nil) where s1.isFinite && s1 >= 0 && s1 <= 360:
                pairSpeed = s1
            case let (nil, s2?) where s2.isFinite && s2 >= 0 && s2 <= 360:
                pairSpeed = s2
            default:
                pairSpeed = nil
            }

            guard let speed = pairSpeed, let band = RouteSpeedBand.classify(speedKmh: speed) else {
                flushCurrent()
                continue
            }

            let startCoord = CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude)
            let endCoord = CLLocationCoordinate2D(latitude: end.latitude, longitude: end.longitude)

            if currentBand == band, !currentCoords.isEmpty {
                currentCoords.append(endCoord)
            } else {
                flushCurrent()
                currentBand = band
                currentCoords = [startCoord, endCoord]
            }
        }

        flushCurrent()
        return result
    }

    private static func downsampleIfNeeded(_ points: [DriveRoutePoint], limit: Int) -> [DriveRoutePoint] {
        guard limit >= 2, points.count > limit else { return points }
        let step = Double(points.count - 1) / Double(limit - 1)
        var indices = Set((0..<limit).map { Int((Double($0) * step).rounded()) })
        indices.insert(0)
        indices.insert(points.count - 1)

        // Preserve segment boundaries so interruption gaps never collapse.
        for index in points.indices.dropFirst() where points[index].segmentIndex != points[index - 1].segmentIndex {
            indices.insert(index - 1)
            indices.insert(index)
        }
        return indices.sorted().map { points[$0] }
    }
}
