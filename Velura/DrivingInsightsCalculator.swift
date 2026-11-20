import Foundation

enum InsightsPeriod: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "Week"
    case month = "Month"
    case all = "All"

    var id: String { rawValue }

    var sectionTitle: String {
        switch self {
        case .today: "TODAY"
        case .week: "THIS WEEK"
        case .month: "THIS MONTH"
        case .all: "ALL TIME"
        }
    }

    var previousLabel: String? {
        switch self {
        case .today: "yesterday"
        case .week: "last week"
        case .month: "last month"
        case .all: nil
        }
    }

    var currentLabel: String {
        switch self {
        case .today: "today"
        case .week: "this week"
        case .month: "this month"
        case .all: "overall"
        }
    }
}

struct InsightBucket: Identifiable, Equatable {
    let index: Int
    let start: Date
    let end: Date
    let distanceKm: Double
    let duration: TimeInterval
    let driveCount: Int
    let label: String
    let detailLabel: String
    let isCurrent: Bool

    var id: Int { index }
}

struct ElevationSample: Identifiable, Equatable {
    let id: Int
    let distanceKm: Double
    let altitudeMeters: Double
}

struct ElevationSummary: Equatable {
    let gainMeters: Double
    let lossMeters: Double
    let minMeters: Double
    let maxMeters: Double
    let samples: [ElevationSample]
}

struct DrivingInsightsSummary: Equatable {
    let driveCount: Int
    let totalDistanceKm: Double
    let totalDuration: TimeInterval
    let movingDuration: TimeInterval
    let hasMovingDurationData: Bool
    let averageSpeedKmh: Double
    let topSpeedKmh: Double?
    let averageDriveDistanceKm: Double
    let elevationGainMeters: Double?
    let elevationLossMeters: Double?
}

enum DrivingInsightsCalculator {
    static let maxVerticalAccuracyMeters: Double = 25
    static let elevationNoiseThresholdMeters: Double = 3.0

    static func calendarWithMondayStart(from base: Calendar = .current) -> Calendar {
        var calendar = base
        calendar.firstWeekday = 2
        return calendar
    }

    static func interval(for period: InsightsPeriod, now: Date = .now, calendar baseCalendar: Calendar = .current) -> DateInterval? {
        let calendar = period == .week ? calendarWithMondayStart(from: baseCalendar) : baseCalendar
        switch period {
        case .today:
            return calendar.dateInterval(of: .day, for: now)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now)
        case .month:
            return calendar.dateInterval(of: .month, for: now)
        case .all:
            return nil
        }
    }

    static func previousInterval(for period: InsightsPeriod, now: Date = .now, calendar baseCalendar: Calendar = .current) -> DateInterval? {
        guard let current = interval(for: period, now: now, calendar: baseCalendar) else { return nil }
        let calendar = period == .week ? calendarWithMondayStart(from: baseCalendar) : baseCalendar
        switch period {
        case .today:
            let start = calendar.date(byAdding: .day, value: -1, to: current.start) ?? current.start
            return DateInterval(start: start, end: current.start)
        case .week:
            let start = calendar.date(byAdding: .day, value: -7, to: current.start) ?? current.start
            return DateInterval(start: start, end: current.start)
        case .month:
            let previousMonthDate = calendar.date(byAdding: .month, value: -1, to: current.start) ?? current.start
            return calendar.dateInterval(of: .month, for: previousMonthDate)
                ?? DateInterval(start: previousMonthDate, end: current.start)
        case .all:
            return nil
        }
    }

    static func drives(
        in period: InsightsPeriod,
        from allDrives: [DriveRecord],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [DriveRecord] {
        guard let range = interval(for: period, now: now, calendar: calendar) else {
            return allDrives
        }
        return allDrives.filter { $0.date >= range.start && $0.date < range.end }
    }

    static func summarize(drives: [DriveRecord]) -> DrivingInsightsSummary {
        let totalDistance = drives.reduce(0.0) { $0 + max(0, $1.distanceKm) }
        let totalDuration = drives.reduce(0.0) { $0 + max(0, $1.duration) }
        let recordedMoving = drives.compactMap(\.movingDuration)
        let hasMoving = !recordedMoving.isEmpty
        let totalMoving = recordedMoving.reduce(0.0) { $0 + max(0, $1) }
        let avgSpeed = totalDuration > 0 && totalDistance > 0
            ? totalDistance / (totalDuration / 3_600)
            : 0
        let topSpeed = drives.map(\.topSpeedKmh).max()
        let avgDistance = drives.isEmpty ? 0 : totalDistance / Double(drives.count)

        var totalGain = 0.0
        var totalLoss = 0.0
        var hasElevation = false
        for drive in drives {
            if let elevation = elevationProfile(for: drive) {
                hasElevation = true
                totalGain += elevation.gainMeters
                totalLoss += elevation.lossMeters
            }
        }

        return DrivingInsightsSummary(
            driveCount: drives.count,
            totalDistanceKm: totalDistance,
            totalDuration: totalDuration,
            movingDuration: totalMoving,
            hasMovingDurationData: hasMoving,
            averageSpeedKmh: avgSpeed,
            topSpeedKmh: topSpeed,
            averageDriveDistanceKm: avgDistance,
            elevationGainMeters: hasElevation ? totalGain : nil,
            elevationLossMeters: hasElevation ? totalLoss : nil
        )
    }

    static func buckets(
        for period: InsightsPeriod,
        drives: [DriveRecord],
        now: Date = .now,
        calendar baseCalendar: Calendar = .current
    ) -> [InsightBucket] {
        switch period {
        case .today:
            guard let dayRange = interval(for: .today, now: now, calendar: baseCalendar) else { return [] }
            let slotHours = 4
            let slotCount = 6
            return (0..<slotCount).compactMap { index in
                guard let start = baseCalendar.date(byAdding: .hour, value: index * slotHours, to: dayRange.start) else { return nil }
                let end = min(
                    baseCalendar.date(byAdding: .hour, value: (index + 1) * slotHours, to: dayRange.start) ?? dayRange.end,
                    dayRange.end
                )
                let matching = drives.filter { $0.date >= start && $0.date < end }
                let hour = baseCalendar.component(.hour, from: start)
                return InsightBucket(
                    index: index,
                    start: start,
                    end: end,
                    distanceKm: matching.reduce(0) { $0 + $1.distanceKm },
                    duration: matching.reduce(0) { $0 + $1.duration },
                    driveCount: matching.count,
                    label: String(format: "%02d", hour),
                    detailLabel: String(format: "%02d:00–%02d:00", hour, min(24, hour + slotHours)),
                    isCurrent: now >= start && now < end
                )
            }

        case .week:
            let calendar = calendarWithMondayStart(from: baseCalendar)
            guard let weekRange = interval(for: .week, now: now, calendar: calendar) else { return [] }
            return (0..<7).compactMap { index in
                guard let start = calendar.date(byAdding: .day, value: index, to: weekRange.start),
                      start < weekRange.end else { return nil }
                let end = min(calendar.date(byAdding: .day, value: index + 1, to: weekRange.start) ?? weekRange.end, weekRange.end)
                let matching = drives.filter { $0.date >= start && $0.date < end }
                return InsightBucket(
                    index: index,
                    start: start,
                    end: end,
                    distanceKm: matching.reduce(0) { $0 + $1.distanceKm },
                    duration: matching.reduce(0) { $0 + $1.duration },
                    driveCount: matching.count,
                    label: start.formatted(.dateTime.weekday(.abbreviated)),
                    detailLabel: start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                    isCurrent: now >= start && now < end
                )
            }

        case .month:
            guard let monthRange = interval(for: .month, now: now, calendar: baseCalendar) else { return [] }
            let dayCount = max(1, baseCalendar.dateComponents([.day], from: monthRange.start, to: monthRange.end).day ?? 30)
            let bucketCount = max(1, Int(ceil(Double(dayCount) / 7)))
            return (0..<bucketCount).compactMap { index in
                let offset = index * 7
                guard let start = baseCalendar.date(byAdding: .day, value: offset, to: monthRange.start),
                      start < monthRange.end else { return nil }
                let end = min(baseCalendar.date(byAdding: .day, value: offset + 7, to: monthRange.start) ?? monthRange.end, monthRange.end)
                let matching = drives.filter { $0.date >= start && $0.date < end }
                let startDay = baseCalendar.component(.day, from: start)
                let endDayDate = baseCalendar.date(byAdding: .day, value: -1, to: end) ?? start
                let endDay = baseCalendar.component(.day, from: endDayDate)
                return InsightBucket(
                    index: index,
                    start: start,
                    end: end,
                    distanceKm: matching.reduce(0) { $0 + $1.distanceKm },
                    duration: matching.reduce(0) { $0 + $1.duration },
                    driveCount: matching.count,
                    label: "\(startDay)",
                    detailLabel: "\(start.formatted(.dateTime.month(.abbreviated))) \(startDay)–\(endDay)",
                    isCurrent: now >= start && now < end
                )
            }

        case .all:
            let monthCount = 6
            let currentMonthStart = baseCalendar.dateInterval(of: .month, for: now)?.start ?? now
            return (0..<monthCount).compactMap { index in
                let offset = -(monthCount - 1 - index)
                guard let monthStart = baseCalendar.date(byAdding: .month, value: offset, to: currentMonthStart),
                      let monthInterval = baseCalendar.dateInterval(of: .month, for: monthStart) else { return nil }
                let matching = drives.filter { $0.date >= monthInterval.start && $0.date < monthInterval.end }
                return InsightBucket(
                    index: index,
                    start: monthInterval.start,
                    end: monthInterval.end,
                    distanceKm: matching.reduce(0) { $0 + $1.distanceKm },
                    duration: matching.reduce(0) { $0 + $1.duration },
                    driveCount: matching.count,
                    label: monthInterval.start.formatted(.dateTime.month(.abbreviated)),
                    detailLabel: monthInterval.start.formatted(.dateTime.month(.wide).year()),
                    isCurrent: now >= monthInterval.start && now < monthInterval.end
                )
            }
        }
    }

    static func elevationProfile(for drive: DriveRecord) -> ElevationSummary? {
        let validAltitudePoints = drive.routeCoordinates.filter { point in
            guard let alt = point.altitudeMeters, alt.isFinite else { return false }
            if let vAcc = point.verticalAccuracy {
                return vAcc.isFinite && vAcc >= 0 && vAcc <= maxVerticalAccuracyMeters
            }
            return true
        }
        guard validAltitudePoints.count >= 2 else { return nil }

        var samples: [ElevationSample] = []
        samples.reserveCapacity(validAltitudePoints.count)

        var cumulativeDistanceKm = 0.0
        var gain = 0.0
        var loss = 0.0
        var anchorAltitude = validAltitudePoints[0].altitudeMeters ?? 0
        var minAltitude = anchorAltitude
        var maxAltitude = anchorAltitude

        for (index, point) in validAltitudePoints.enumerated() {
            let altitude = point.altitudeMeters ?? anchorAltitude
            if index > 0 {
                let prev = validAltitudePoints[index - 1]
                if prev.segmentIndex == point.segmentIndex {
                    cumulativeDistanceKm += haversineKm(
                        lat1: prev.latitude, lon1: prev.longitude,
                        lat2: point.latitude, lon2: point.longitude
                    )
                    let delta = altitude - anchorAltitude
                    if abs(delta) >= elevationNoiseThresholdMeters {
                        if delta > 0 {
                            gain += delta
                        } else {
                            loss += -delta
                        }
                        anchorAltitude = altitude
                    }
                } else {
                    anchorAltitude = altitude
                }
            }

            minAltitude = min(minAltitude, altitude)
            maxAltitude = max(maxAltitude, altitude)
            samples.append(ElevationSample(id: index, distanceKm: cumulativeDistanceKm, altitudeMeters: altitude))
        }

        let downsampled = downsampleElevationSamples(samples, maxCount: 60)
        return ElevationSummary(
            gainMeters: gain,
            lossMeters: loss,
            minMeters: minAltitude,
            maxMeters: maxAltitude,
            samples: downsampled
        )
    }

    private static func downsampleElevationSamples(_ samples: [ElevationSample], maxCount: Int) -> [ElevationSample] {
        guard samples.count > maxCount, maxCount >= 2 else { return samples }
        let step = Double(samples.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { idx in
            let sourceIndex = min(samples.count - 1, Int((Double(idx) * step).rounded()))
            let sample = samples[sourceIndex]
            return ElevationSample(id: idx, distanceKm: sample.distanceKm, altitudeMeters: sample.altitudeMeters)
        }
    }

    private static func haversineKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthRadiusKm = 6_371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(0, 1 - a)))
        return earthRadiusKm * c
    }
}
