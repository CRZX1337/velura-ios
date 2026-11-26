import Foundation
import Testing

#if canImport(FoundationXML)
import FoundationXML
#endif
@testable import VeluraCore

// Portable mirror of the device-side suite (VeluraTests.swift). These tests cover the
// slice of Velura that has no Apple-only dependency, so they also run on Windows/Linux.

struct PortableLogicTests {
    @Test func migratesLegacyDriveHistoryToVersionedFiles() throws {
        let (root, defaults, suiteName) = temporaryHistoryStorage()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let route = [DriveRoutePoint(latitude: 37, longitude: -122, timestamp: Date(timeIntervalSince1970: 1_000))]
        let drive = DriveRecord(date: Date(timeIntervalSince1970: 900), duration: 60, distanceKm: 2, topSpeedKmh: 50, routeCoordinates: route)
        let legacyData = try JSONEncoder().encode([drive])
        defaults.set(legacyData, forKey: DriveHistoryFileStorage.legacyStorageKey)

        let storage = DriveHistoryFileStorage(baseDirectoryURL: root, defaults: defaults)
        let result = storage.load()

        #expect(result.errorMessage == nil)
        #expect(result.drives == [drive])
        #expect(defaults.data(forKey: DriveHistoryFileStorage.legacyStorageKey) == nil)
        let recordURL = storage.recordFileURL(for: drive.id)
        #expect(recordURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)
    }

    @Test func persistsAndDeletesDriveFilesWithoutLosingRoutes() throws {
        let (root, defaults, suiteName) = temporaryHistoryStorage()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let route = [DriveRoutePoint(latitude: 37, longitude: -122, timestamp: Date(timeIntervalSince1970: 1_000))]
        let drive = DriveRecord(date: Date(timeIntervalSince1970: 900), duration: 60, distanceKm: 2, topSpeedKmh: 50, routeCoordinates: route)
        let storage = DriveHistoryFileStorage(baseDirectoryURL: root, defaults: defaults)
        try storage.upsert(drive)
        #expect(storage.load().drives == [drive])

        try storage.delete(drive.id)
        #expect(storage.load().drives.isEmpty)
    }

    @Test func exportsValidGPXWithCoordinatesTimestampsElevationAndSpeedExtensions() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let route = [
            DriveRoutePoint(latitude: 48.137154, longitude: 11.576124, timestamp: start, segmentIndex: 0, speedKmh: 36, altitudeMeters: 520.5, verticalAccuracy: 6),
            DriveRoutePoint(latitude: 48.138000, longitude: 11.577200, timestamp: start.addingTimeInterval(10), segmentIndex: 0, speedKmh: 72, altitudeMeters: 524.0, verticalAccuracy: 40),
            DriveRoutePoint(latitude: 48.139000, longitude: 11.578500, timestamp: start.addingTimeInterval(30), segmentIndex: 1, speedKmh: 108, altitudeMeters: nil, verticalAccuracy: nil),
        ]
        let drive = DriveRecord(date: start, duration: 30, distanceKm: 0.4, topSpeedKmh: 108, routeCoordinates: route)
        let xml = try GPXExporter.makeGPXString(for: drive, trackName: "Test & <Route> \"1\"")

        #expect(xml.contains(#"<?xml version="1.0" encoding="UTF-8"?>"#))
        #expect(xml.contains(#"<gpx version="1.1""#))
        #expect(xml.contains("Test &amp; &lt;Route&gt; &quot;1&quot;"))
        #expect(xml.contains(#"lat="48.1371540" lon="11.5761240""#))
        #expect(xml.contains("<ele>520.50</ele>"))
        #expect(!xml.contains("<ele>524.00</ele>"))
        #expect(xml.contains("<velura:speedKmh>36.00</velura:speedKmh>"))
        #expect(xml.contains("<velura:speedMps>10.000</velura:speedMps>"))

        let validator = GPXXMLValidator()
        #expect(validator.parse(xml: xml))
        #expect(validator.trackSegmentCount == 2)
        #expect(validator.trackPointCount == 3)
    }

    @Test func rejectsGPXExportForEmptyOrInvalidRoutes() {
        let emptyDrive = DriveRecord(date: Date(timeIntervalSince1970: 1_000), duration: 60, distanceKm: 1, topSpeedKmh: 50, routeCoordinates: [])
        #expect(throws: GPXExportError.emptyRoute) {
            _ = try GPXExporter.makeGPXString(for: emptyDrive)
        }

        let invalidDrive = DriveRecord(
            date: Date(timeIntervalSince1970: 1_000),
            duration: 60,
            distanceKm: 1,
            topSpeedKmh: 50,
            routeCoordinates: [DriveRoutePoint(latitude: 120, longitude: 200, timestamp: Date(timeIntervalSince1970: 1_000))]
        )
        #expect(throws: GPXExportError.noValidCoordinates) {
            _ = try GPXExporter.makeGPXString(for: invalidDrive)
        }
    }

    @Test func generatesDeterministicGPXFilenameWithDateAndTime() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let drive = DriveRecord(date: date, duration: 60, distanceKm: 1, topSpeedKmh: 50)
        let filename = GPXExporter.suggestedFilename(for: drive, timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(filename == "Velura-Drive-2023-11-14_22-13-20.gpx")
    }

    @Test func aggregatesInsightsAcrossPeriodsAndTimezonesAndComputesElevation() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3600)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 15, minute: 0))!
        let mondayDriveDate = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9, minute: 0))!
        let lastWeekDate = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12, minute: 0))!

        let elevationRoute = [
            DriveRoutePoint(latitude: 48.0, longitude: 11.0, timestamp: now, altitudeMeters: 500, verticalAccuracy: 5),
            DriveRoutePoint(latitude: 48.002, longitude: 11.0, timestamp: now.addingTimeInterval(10), altitudeMeters: 501, verticalAccuracy: 5),
            DriveRoutePoint(latitude: 48.004, longitude: 11.0, timestamp: now.addingTimeInterval(20), altitudeMeters: 520, verticalAccuracy: 5),
            DriveRoutePoint(latitude: 48.006, longitude: 11.0, timestamp: now.addingTimeInterval(30), altitudeMeters: 510, verticalAccuracy: 5),
            DriveRoutePoint(latitude: 48.008, longitude: 11.0, timestamp: now.addingTimeInterval(40), altitudeMeters: 900, verticalAccuracy: 80),
        ]

        let todayDrive = DriveRecord(date: now.addingTimeInterval(-1_800), duration: 1_800, movingDuration: 1_500, distanceKm: 30, topSpeedKmh: 110, routeCoordinates: elevationRoute)
        let mondayDrive = DriveRecord(date: mondayDriveDate, duration: 3_600, movingDuration: 3_000, distanceKm: 60, topSpeedKmh: 130)
        let oldDrive = DriveRecord(date: lastWeekDate, duration: 1_200, distanceKm: 15, topSpeedKmh: 80)

        let allDrives = [todayDrive, mondayDrive, oldDrive]
        #expect(DrivingInsightsCalculator.drives(in: .today, from: allDrives, now: now, calendar: calendar).count == 1)
        let weekFiltered = DrivingInsightsCalculator.drives(in: .week, from: allDrives, now: now, calendar: calendar)
        #expect(weekFiltered.count == 2)

        let weekSummary = DrivingInsightsCalculator.summarize(drives: weekFiltered)
        #expect(weekSummary.driveCount == 2)
        #expect(weekSummary.totalDistanceKm == 90)
        #expect(weekSummary.totalDuration == 5_400)
        #expect(weekSummary.movingDuration == 4_500)
        #expect(abs(weekSummary.averageSpeedKmh - 60) < 0.01)
        #expect(weekSummary.topSpeedKmh == 130)
        #expect(weekSummary.elevationGainMeters == 20)
        #expect(weekSummary.elevationLossMeters == 10)

        let weekBuckets = DrivingInsightsCalculator.buckets(for: .week, drives: weekFiltered, now: now, calendar: calendar)
        #expect(weekBuckets.count == 7)
        #expect(weekBuckets[0].distanceKm == 60)
        #expect(weekBuckets[2].distanceKm == 30)
        #expect(weekBuckets[2].isCurrent)
    }

    @Test func decodesLegacyDriveRecordAndMetadataWithoutNewOptionalFields() throws {
        let legacyRecordJSON = """
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "date": 1000,
          "duration": 120,
          "distanceKm": 2.4,
          "topSpeedKmh": 65,
          "routeCoordinates": [
            { "latitude": 48.1, "longitude": 11.5, "timestamp": 1000, "segmentIndex": 0 }
          ],
          "interruptionGaps": []
        }
        """
        let decoded = try JSONDecoder().decode(DriveRecord.self, from: Data(legacyRecordJSON.utf8))
        #expect(decoded.movingDuration == nil)
        #expect(decoded.pausedDuration == nil)
        #expect(decoded.routeCoordinates.first?.speedKmh == nil)
        #expect(decoded.routeCoordinates.first?.altitudeMeters == nil)
        #expect(abs(decoded.averageSpeedKmh - 72) < 0.01)
    }

    @Test func checkpointsActiveRouteIncrementallyAndRestoresIt() throws {
        let (root, defaults, suiteName) = temporaryHistoryStorage()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let sessionID = UUID()
        let base = Date(timeIntervalSince1970: 5_000)
        let storage = ActiveDriveFileStorage(baseDirectoryURL: root)
        try storage.save(activeMetadata(sessionID: sessionID, routePointCount: 0, at: base))

        let points = [
            DriveRoutePoint(latitude: 48.0, longitude: 11.0, timestamp: base),
            DriveRoutePoint(latitude: 48.001, longitude: 11.0, timestamp: base.addingTimeInterval(5)),
        ]
        for (index, point) in points.enumerated() {
            try storage.appendRoutePoint(sessionID: sessionID, index: index, point: point, forceFlush: index == points.count - 1)
        }
        try storage.save(activeMetadata(sessionID: sessionID, routePointCount: 2, at: base.addingTimeInterval(5)))

        let reloaded = ActiveDriveFileStorage(baseDirectoryURL: root).load()
        #expect(reloaded.errorMessage == nil)
        #expect(reloaded.snapshot?.routeCoordinates == points)
    }

    private func temporaryHistoryStorage() -> (URL, UserDefaults, String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VeluraLogic-\(UUID().uuidString)")
        let suiteName = "VeluraLogicTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (root, defaults, suiteName)
    }

    private func activeMetadata(sessionID: UUID, routePointCount: Int, at date: Date) -> ActiveDriveMetadata {
        ActiveDriveMetadata(
            sessionID: sessionID,
            startedAt: date.addingTimeInterval(-60),
            elapsedSeconds: 60,
            distanceKm: 1.2,
            topSpeedKmh: 55,
            routePointCount: routePointCount,
            updatedAt: date,
            lastLocationAt: date,
            routeSegmentIndex: 0,
            interruptionGaps: [],
            pendingGapStartAt: nil
        )
    }
}

private final class GPXXMLValidator: NSObject, XMLParserDelegate {
    private(set) var trackSegmentCount = 0
    private(set) var trackPointCount = 0

    func parse(xml: String) -> Bool {
        trackSegmentCount = 0
        trackPointCount = 0
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = self
        return parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if elementName == "trkseg" {
            trackSegmentCount += 1
        } else if elementName == "trkpt" {
            trackPointCount += 1
        }
    }
}
