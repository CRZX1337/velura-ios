import CoreLocation
import Foundation
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
        let outlier = location(latitude: 37, longitude: -121.99, accuracy: 5, speed: 5, at: timestamp.addingTimeInterval(1))
        let sample = location(latitude: 37, longitude: -121.9999, accuracy: 5, speed: 5, at: timestamp.addingTimeInterval(2))

        #expect(filter.issue(for: outlier, receivedAt: outlier.timestamp, previousLocation: previous) == .implausible)
        #expect(filter.issue(for: sample, receivedAt: sample.timestamp, previousLocation: previous) == nil)
    }

    @Test func keepsLastAcceptedGPSFixFreshOnlyWithinTheExistingWindow() {
        let timestamp = Date(timeIntervalSince1970: 1_000)

        #expect(GPSLocationFilter.isFresh(lastAcceptedAt: timestamp, now: timestamp.addingTimeInterval(5)))
        #expect(!GPSLocationFilter.isFresh(lastAcceptedAt: timestamp, now: timestamp.addingTimeInterval(5.1)))
    }

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
        #expect(recordURL != nil && FileManager.default.fileExists(atPath: recordURL!.path))
    }

    @Test func keepsLegacyHistoryWhenMigrationCannotWrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VeluraMigrationBlocker-\(UUID().uuidString)")
        try Data([0x01]).write(to: root)
        let suiteName = "VeluraTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let drive = DriveRecord(date: Date(timeIntervalSince1970: 900), duration: 60, distanceKm: 2, topSpeedKmh: 50)
        let legacyData = try JSONEncoder().encode([drive])
        defaults.set(legacyData, forKey: DriveHistoryFileStorage.legacyStorageKey)
        let storage = DriveHistoryFileStorage(baseDirectoryURL: root, defaults: defaults)

        let result = storage.load()

        #expect(result.drives == [drive])
        #expect(result.errorMessage != nil)
        #expect(defaults.data(forKey: DriveHistoryFileStorage.legacyStorageKey) == legacyData)
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

        var withoutRoute = drive
        withoutRoute.routeCoordinates.removeAll()
        try storage.upsert(withoutRoute)
        #expect(storage.load().drives.first?.routeCoordinates.isEmpty == true)

        try storage.delete(drive.id)
        #expect(storage.load().drives.isEmpty)
        try storage.upsert(drive)
        try storage.clear()
        #expect(storage.load().drives.isEmpty)
    }

    @Test func restoresHistoryFromAStagedClearAndClearsTheBackup() throws {
        let (root, defaults, suiteName) = temporaryHistoryStorage()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let drive = DriveRecord(date: Date(timeIntervalSince1970: 1_500), duration: 90, distanceKm: 3, topSpeedKmh: 60)
        let storage = DriveHistoryFileStorage(baseDirectoryURL: root, defaults: defaults)
        try storage.upsert(drive)
        let recordsDirectory = storage.recordFileURL(for: drive.id)!.deletingLastPathComponent()
        let backupDirectory = root.appendingPathComponent("DriveHistory-clearing-recovery", isDirectory: true)
        try FileManager.default.moveItem(at: recordsDirectory, to: backupDirectory)

        #expect(storage.load().drives == [drive])
        try storage.delete(drive.id)
        #expect(storage.load().drives.isEmpty)
        try storage.clear()
        #expect(!FileManager.default.fileExists(atPath: backupDirectory.path))

        try storage.upsert(drive)
        let updatedRecordsDirectory = storage.recordFileURL(for: drive.id)!.deletingLastPathComponent()
        try FileManager.default.moveItem(at: updatedRecordsDirectory, to: backupDirectory)
        #expect(storage.load().drives == [drive])
        try storage.clear()
        #expect(storage.load().drives.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: backupDirectory.path))
    }

    @Test func checkpointsActiveRouteIncrementallyAndRestoresIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VeluraActiveDrive-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 2_000)
        let first = DriveRoutePoint(latitude: 37, longitude: -122, timestamp: timestamp)
        let second = DriveRoutePoint(latitude: 37.001, longitude: -122, timestamp: timestamp.addingTimeInterval(5), segmentIndex: 1)
        let storage = ActiveDriveFileStorage(baseDirectoryURL: root)
        try storage.save(activeMetadata(sessionID: sessionID, routePointCount: 0, at: timestamp))
        try storage.appendRoutePoint(sessionID: sessionID, index: 0, point: first)
        try storage.appendRoutePoint(sessionID: sessionID, index: 1, point: second)
        try storage.save(activeMetadata(sessionID: sessionID, routePointCount: 2, at: timestamp.addingTimeInterval(5)))

        let result = ActiveDriveFileStorage(baseDirectoryURL: root).load()

        #expect(result.errorMessage == nil)
        #expect(result.snapshot?.routeCoordinates == [first, second])
    }

    @Test func restoresActiveDriveFromAStagedClearBeforeAppendingMoreRoutePoints() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VeluraActiveDriveRecovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 2_500)
        let first = DriveRoutePoint(latitude: 37, longitude: -122, timestamp: timestamp)
        let second = DriveRoutePoint(latitude: 37.001, longitude: -122, timestamp: timestamp.addingTimeInterval(5))
        let storage = ActiveDriveFileStorage(baseDirectoryURL: root)
        try storage.save(activeMetadata(sessionID: sessionID, routePointCount: 0, at: timestamp))
        try storage.appendRoutePoint(sessionID: sessionID, index: 0, point: first)
        try storage.save(activeMetadata(sessionID: sessionID, routePointCount: 1, at: timestamp))

        let backupDirectory = root.appendingPathComponent("ActiveDrive-clearing-recovery", isDirectory: true)
        try FileManager.default.moveItem(
            at: root.appendingPathComponent("ActiveDrive-v1", isDirectory: true),
            to: backupDirectory
        )
        let recoveringStorage = ActiveDriveFileStorage(baseDirectoryURL: root)
        let recovered = recoveringStorage.load()

        #expect(recovered.errorMessage == nil)
        #expect(recovered.snapshot?.routeCoordinates == [first])
        try recoveringStorage.appendRoutePoint(sessionID: sessionID, index: 1, point: second)
        try recoveringStorage.save(activeMetadata(sessionID: sessionID, routePointCount: 2, at: timestamp.addingTimeInterval(5)))

        let reloaded = ActiveDriveFileStorage(baseDirectoryURL: root).load()
        #expect(reloaded.errorMessage == nil)
        #expect(reloaded.snapshot?.routeCoordinates == [first, second])
        #expect(!FileManager.default.fileExists(atPath: backupDirectory.path))
    }

    @Test func repairsAnIncompleteRouteJournalBeforeFurtherAppends() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VeluraRouteRepair-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 2_750)
        let first = DriveRoutePoint(latitude: 37, longitude: -122, timestamp: timestamp)
        let second = DriveRoutePoint(latitude: 37.001, longitude: -122, timestamp: timestamp.addingTimeInterval(5))
        let storage = ActiveDriveFileStorage(baseDirectoryURL: root)
        try storage.save(activeMetadata(sessionID: sessionID, routePointCount: 0, at: timestamp))
        try storage.appendRoutePoint(sessionID: sessionID, index: 0, point: first)
        try storage.save(activeMetadata(sessionID: sessionID, routePointCount: 1, at: timestamp))

        let journalURL = root.appendingPathComponent("ActiveDrive-v1/route.jsonl")
        var journalData = try Data(contentsOf: journalURL)
        journalData.append(contentsOf: Data("{incomplete".utf8))
        try journalData.write(to: journalURL)

        let recoveringStorage = ActiveDriveFileStorage(baseDirectoryURL: root)
        let recovered = recoveringStorage.load()
        #expect(recovered.snapshot?.routeCoordinates == [first])
        #expect(recovered.errorMessage != nil)
        try recoveringStorage.appendRoutePoint(sessionID: sessionID, index: 1, point: second)
        try recoveringStorage.save(activeMetadata(sessionID: sessionID, routePointCount: 2, at: timestamp.addingTimeInterval(5)))

        let reloaded = ActiveDriveFileStorage(baseDirectoryURL: root).load()
        #expect(reloaded.errorMessage == nil)
        #expect(reloaded.snapshot?.routeCoordinates == [first, second])
    }

    @Test func keepsLegacyActiveDriveRecoverableWhenMigrationInitiallyFails() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VeluraActiveDriveMigrationRetry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let timestamp = Date(timeIntervalSince1970: 3_250)
        let sessionID = UUID()
        let first = DriveRoutePoint(latitude: 37, longitude: -122, timestamp: timestamp)
        let second = DriveRoutePoint(latitude: 37.001, longitude: -122, timestamp: timestamp.addingTimeInterval(5))
        let snapshot = ActiveDriveSnapshot(
            sessionID: sessionID,
            startedAt: timestamp.addingTimeInterval(-60),
            elapsedSeconds: 60,
            distanceKm: 1.2,
            topSpeedKmh: 55,
            routeCoordinates: [first],
            updatedAt: timestamp,
            lastLocationAt: timestamp,
            routeSegmentIndex: 0,
            interruptionGaps: [],
            pendingGapStartAt: nil
        )
        try JSONEncoder().encode(snapshot).write(to: root.appendingPathComponent("active-drive.json"))
        let blockerURL = root.appendingPathComponent("ActiveDrive-v1")
        try Data([0x01]).write(to: blockerURL)
        let storage = ActiveDriveFileStorage(baseDirectoryURL: root)

        let firstLoad = storage.load()
        #expect(firstLoad.snapshot == snapshot)
        #expect(firstLoad.errorMessage != nil)

        try FileManager.default.removeItem(at: blockerURL)
        try storage.appendRoutePoint(sessionID: sessionID, index: 1, point: second)
        try storage.save(activeMetadata(sessionID: sessionID, routePointCount: 2, at: timestamp.addingTimeInterval(5)))
        let recovered = ActiveDriveFileStorage(baseDirectoryURL: root).load()

        #expect(recovered.errorMessage == nil)
        #expect(recovered.snapshot?.routeCoordinates == [first, second])
    }

    @Test func prefersVersionedActiveDriveOverAnOldLegacySnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VeluraActiveDriveMigrationRecovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let timestamp = Date(timeIntervalSince1970: 3_500)
        let legacySnapshot = ActiveDriveSnapshot(
            sessionID: UUID(),
            startedAt: timestamp.addingTimeInterval(-60),
            elapsedSeconds: 60,
            distanceKm: 1.2,
            topSpeedKmh: 55,
            routeCoordinates: [],
            updatedAt: timestamp,
            lastLocationAt: timestamp,
            routeSegmentIndex: 0,
            interruptionGaps: [],
            pendingGapStartAt: nil
        )
        let legacyURL = root.appendingPathComponent("active-drive.json")
        try JSONEncoder().encode(legacySnapshot).write(to: legacyURL)
        let storage = ActiveDriveFileStorage(baseDirectoryURL: root)
        #expect(storage.load().snapshot == legacySnapshot)

        var updatedSnapshot = legacySnapshot
        updatedSnapshot.elapsedSeconds = 120
        updatedSnapshot.updatedAt = timestamp.addingTimeInterval(60)
        try storage.save(ActiveDriveMetadata(snapshot: updatedSnapshot, routePointCount: 0))
        try JSONEncoder().encode(legacySnapshot).write(to: legacyURL)

        let result = ActiveDriveFileStorage(baseDirectoryURL: root).load()

        #expect(result.errorMessage == nil)
        #expect(result.snapshot?.elapsedSeconds == 120)
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
    }

    @Test func migratesLegacyActiveDriveSnapshotWithItsRoute() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VeluraLegacyActiveDrive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let timestamp = Date(timeIntervalSince1970: 3_000)
        let route = [
            DriveRoutePoint(latitude: 37, longitude: -122, timestamp: timestamp),
            DriveRoutePoint(latitude: 37.001, longitude: -122, timestamp: timestamp.addingTimeInterval(5), segmentIndex: 1)
        ]
        let snapshot = ActiveDriveSnapshot(
            sessionID: UUID(),
            startedAt: timestamp.addingTimeInterval(-60),
            elapsedSeconds: 60,
            distanceKm: 1.2,
            topSpeedKmh: 55,
            routeCoordinates: route,
            updatedAt: timestamp,
            lastLocationAt: timestamp,
            routeSegmentIndex: 1,
            interruptionGaps: [DriveInterruptionGap(startAt: timestamp.addingTimeInterval(-10), endAt: timestamp)],
            pendingGapStartAt: nil
        )
        let legacyURL = root.appendingPathComponent("active-drive.json")
        try JSONEncoder().encode(snapshot).write(to: legacyURL)

        let result = ActiveDriveFileStorage(baseDirectoryURL: root).load()

        #expect(result.errorMessage == nil)
        #expect(result.snapshot == snapshot)
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path))
    }

    @Test func acceptsInitialValidCoordinateWhenReportedSpeedIsUnknown() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let sample = location(latitude: 37, longitude: -122, accuracy: 8, speed: -1, at: timestamp)

        #expect(filter.issue(for: sample, receivedAt: timestamp, previousLocation: nil) == nil)
    }

    @Test func rejectsOutlierPositionJumpEvenWhenReportedSpeedIsUnknown() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let previous = location(latitude: 37, longitude: -122, accuracy: 5, speed: -1, at: timestamp)
        let jump = location(latitude: 37, longitude: -121.99, accuracy: 5, speed: -1, at: timestamp.addingTimeInterval(1))

        #expect(filter.issue(for: jump, receivedAt: jump.timestamp, previousLocation: previous) == .implausible)
    }

    @Test func smoothsDisplaySpeedWhileSnappingBelowOneKmhToZero() {
        var smoother = SpeedDisplaySmoother()

        let first = smoother.update(rawSpeedKmh: 50)
        #expect(first == 50)

        let second = smoother.update(rawSpeedKmh: 60)
        #expect(second > 50 && second < 60)

        let stopped = smoother.update(rawSpeedKmh: 0.4)
        #expect(stopped == 0)

        smoother.reset()
        #expect(smoother.smoothedValue == 0)
    }

    @Test func batchesRoutePointsAndFlushesOnSaveOrExplicitFlush() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VeluraBatchFlush-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sessionID = UUID()
        let timestamp = Date(timeIntervalSince1970: 4_000)
        let points = (0..<3).map { offset in
            DriveRoutePoint(
                latitude: 37 + Double(offset) * 0.001,
                longitude: -122,
                timestamp: timestamp.addingTimeInterval(Double(offset) * 2),
                speedKmh: 45 + Double(offset) * 15,
                altitudeMeters: 120 + Double(offset) * 5,
                verticalAccuracy: 4
            )
        }
        let storage = ActiveDriveFileStorage(baseDirectoryURL: root)
        try storage.save(activeMetadata(sessionID: sessionID, routePointCount: 0, at: timestamp))
        for (index, point) in points.enumerated() {
            try storage.appendRoutePoint(sessionID: sessionID, index: index, point: point)
        }
        try storage.flushPendingRoutePointsIfNeeded()
        try storage.save(activeMetadata(sessionID: sessionID, routePointCount: points.count, at: timestamp.addingTimeInterval(6)))

        let reloaded = ActiveDriveFileStorage(baseDirectoryURL: root).load()
        #expect(reloaded.errorMessage == nil)
        #expect(reloaded.snapshot?.routeCoordinates == points)
    }

    @Test func exportsValidGPXWithCoordinatesTimestampsElevationAndSpeedExtensions() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let route = [
            DriveRoutePoint(
                latitude: 48.137154,
                longitude: 11.576124,
                timestamp: start,
                segmentIndex: 0,
                speedKmh: 36,
                altitudeMeters: 520.5,
                verticalAccuracy: 6
            ),
            DriveRoutePoint(
                latitude: 48.138000,
                longitude: 11.577200,
                timestamp: start.addingTimeInterval(10),
                segmentIndex: 0,
                speedKmh: 72,
                altitudeMeters: 524.0,
                verticalAccuracy: 40 // Inaccurate elevation must be omitted
            ),
            DriveRoutePoint(
                latitude: 48.139000,
                longitude: 11.578500,
                timestamp: start.addingTimeInterval(30),
                segmentIndex: 1,
                speedKmh: 108,
                altitudeMeters: nil,
                verticalAccuracy: nil
            )
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
        #expect(xml.contains("<velura:speedKmh>108.00</velura:speedKmh>"))

        // Verify valid XML via Foundation XMLParser and separate trkseg per segmentIndex
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
            routeCoordinates: [
                DriveRoutePoint(latitude: 120, longitude: 200, timestamp: Date(timeIntervalSince1970: 1_000))
            ]
        )
        #expect(throws: GPXExportError.noValidCoordinates) {
            _ = try GPXExporter.makeGPXString(for: invalidDrive)
        }
    }

    @Test func generatesDeterministicGPXFilenameWithDateAndTime() {
        let date = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13:20 UTC
        let drive = DriveRecord(date: date, duration: 60, distanceKm: 1, topSpeedKmh: 50)
        let filename = GPXExporter.suggestedFilename(for: drive, timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(filename == "Velura-Drive-2023-11-14_22-13-20.gpx")
    }

    @Test func classifiesSpeedHeatmapBandsAndRejectsOutliers() {
        #expect(RouteSpeedBand.classify(speedKmh: 0) == .slow)
        #expect(RouteSpeedBand.classify(speedKmh: 49.9) == .slow)
        #expect(RouteSpeedBand.classify(speedKmh: 50) == .moderate)
        #expect(RouteSpeedBand.classify(speedKmh: 89.9) == .moderate)
        #expect(RouteSpeedBand.classify(speedKmh: 90) == .fast)
        #expect(RouteSpeedBand.classify(speedKmh: 360) == .fast)
        #expect(RouteSpeedBand.classify(speedKmh: -1) == nil)
        #expect(RouteSpeedBand.classify(speedKmh: 400) == nil)
        #expect(RouteSpeedBand.classify(speedKmh: .nan) == nil)
    }

    @Test func buildsHeatmapSegmentsRespectingGapsAndHistoricalRoutesWithoutSpeed() {
        let start = Date(timeIntervalSince1970: 2_000)
        let historicalPoints = [
            DriveRoutePoint(latitude: 48.0, longitude: 11.0, timestamp: start, segmentIndex: 0),
            DriveRoutePoint(latitude: 48.001, longitude: 11.001, timestamp: start.addingTimeInterval(5), segmentIndex: 0)
        ]
        #expect(!RouteSpeedHeatmapBuilder.hasSpeedData(in: historicalPoints))
        #expect(RouteSpeedHeatmapBuilder.buildSegments(from: historicalPoints).isEmpty)

        let speedPoints = [
            DriveRoutePoint(latitude: 48.0, longitude: 11.0, timestamp: start, segmentIndex: 0, speedKmh: 30),
            DriveRoutePoint(latitude: 48.001, longitude: 11.0, timestamp: start.addingTimeInterval(5), segmentIndex: 0, speedKmh: 40),
            DriveRoutePoint(latitude: 48.002, longitude: 11.0, timestamp: start.addingTimeInterval(10), segmentIndex: 0, speedKmh: 110),
            DriveRoutePoint(latitude: 48.003, longitude: 11.0, timestamp: start.addingTimeInterval(15), segmentIndex: 0, speedKmh: 120),
            // Interruption gap -> new segmentIndex
            DriveRoutePoint(latitude: 48.010, longitude: 11.0, timestamp: start.addingTimeInterval(60), segmentIndex: 1, speedKmh: 120),
            DriveRoutePoint(latitude: 48.011, longitude: 11.0, timestamp: start.addingTimeInterval(65), segmentIndex: 1, speedKmh: 120)
        ]
        #expect(RouteSpeedHeatmapBuilder.hasSpeedData(in: speedPoints))
        let segments = RouteSpeedHeatmapBuilder.buildSegments(from: speedPoints)
        #expect(segments.count == 4) // slow (30-40), moderate (40-110 avg 75), fast (110-120), fast in segment 1
        #expect(segments.first?.band == .slow)
        #expect(segments.last?.band == .fast)
        #expect(segments.last?.coordinates.count == 2)
    }

    @Test func aggregatesInsightsAcrossPeriodsAndTimezonesAndComputesElevation() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 3600)! // UTC+1
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 15, minute: 0))! // Wednesday
        let mondayDriveDate = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 9, minute: 0))!
        let lastWeekDate = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12, minute: 0))!

        let elevationRoute = [
            DriveRoutePoint(latitude: 48.0, longitude: 11.0, timestamp: now, altitudeMeters: 500, verticalAccuracy: 5),
            DriveRoutePoint(latitude: 48.002, longitude: 11.0, timestamp: now.addingTimeInterval(10), altitudeMeters: 501, verticalAccuracy: 5), // within noise threshold
            DriveRoutePoint(latitude: 48.004, longitude: 11.0, timestamp: now.addingTimeInterval(20), altitudeMeters: 520, verticalAccuracy: 5), // +20m
            DriveRoutePoint(latitude: 48.006, longitude: 11.0, timestamp: now.addingTimeInterval(30), altitudeMeters: 510, verticalAccuracy: 5), // -10m
            DriveRoutePoint(latitude: 48.008, longitude: 11.0, timestamp: now.addingTimeInterval(40), altitudeMeters: 900, verticalAccuracy: 80) // rejected inaccurate
        ]

        let todayDrive = DriveRecord(
            date: now.addingTimeInterval(-1_800),
            duration: 1_800,
            movingDuration: 1_500,
            distanceKm: 30,
            topSpeedKmh: 110,
            routeCoordinates: elevationRoute
        )
        let mondayDrive = DriveRecord(
            date: mondayDriveDate,
            duration: 3_600,
            movingDuration: 3_000,
            distanceKm: 60,
            topSpeedKmh: 130
        )
        let oldDrive = DriveRecord(
            date: lastWeekDate,
            duration: 1_200,
            distanceKm: 15,
            topSpeedKmh: 80
        )

        let allDrives = [todayDrive, mondayDrive, oldDrive]
        let todayFiltered = DrivingInsightsCalculator.drives(in: .today, from: allDrives, now: now, calendar: calendar)
        #expect(todayFiltered.count == 1)

        let weekFiltered = DrivingInsightsCalculator.drives(in: .week, from: allDrives, now: now, calendar: calendar)
        #expect(weekFiltered.count == 2)

        let weekSummary = DrivingInsightsCalculator.summarize(drives: weekFiltered)
        #expect(weekSummary.driveCount == 2)
        #expect(weekSummary.totalDistanceKm == 90)
        #expect(weekSummary.totalDuration == 5_400)
        #expect(weekSummary.movingDuration == 4_500)
        #expect(weekSummary.hasMovingDurationData)
        #expect(abs(weekSummary.averageSpeedKmh - 60) < 0.01)
        #expect(weekSummary.topSpeedKmh == 130)
        #expect(weekSummary.elevationGainMeters == 20)
        #expect(weekSummary.elevationLossMeters == 10)

        let weekBuckets = DrivingInsightsCalculator.buckets(for: .week, drives: weekFiltered, now: now, calendar: calendar)
        #expect(weekBuckets.count == 7)
        #expect(weekBuckets[0].distanceKm == 60) // Monday
        #expect(weekBuckets[2].distanceKm == 30) // Wednesday (today)
        #expect(weekBuckets[2].isCurrent)

        let todayBuckets = DrivingInsightsCalculator.buckets(for: .today, drives: todayFiltered, now: now, calendar: calendar)
        #expect(todayBuckets.count == 6)
        #expect(todayBuckets.reduce(0) { $0 + $1.distanceKm } == 30)
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

        let legacyMetadataJSON = """
        {
          "sessionID": "11111111-2222-3333-4444-555555555555",
          "startedAt": 1000,
          "elapsedSeconds": 120,
          "distanceKm": 2.4,
          "topSpeedKmh": 65,
          "routePointCount": 1,
          "updatedAt": 1120,
          "routeSegmentIndex": 0,
          "interruptionGaps": []
        }
        """
        let decodedMeta = try JSONDecoder().decode(ActiveDriveMetadata.self, from: Data(legacyMetadataJSON.utf8))
        #expect(decodedMeta.movingSeconds == 0)
        #expect(decodedMeta.pausedSeconds == 0)
    }

    @Test @MainActor func transitionsDriveStatesCleanlyOnPauseAndReset() {
        let model = SpeedometerModel()
        #expect(model.driveState == .idle)
        #expect(model.elapsedTime() == 0)
        #expect(model.movingTime() == 0)
        #expect(model.pausedTime() == 0)
        #expect(model.averageSpeedKmh() == 0)

        // Pausing while idle must be a no-op and preserve idle state.
        model.pauseSession()
        #expect(model.driveState == .idle)
        #expect(!model.isSessionActive)

        // Reset clears metrics cleanly.
        model.resetSession()
        #expect(model.driveState == .idle)
        #expect(model.speedKmh == 0)
        #expect(model.displaySpeedKmh == 0)
    }

    @Test @MainActor func tracksActivePausedAndResumedSegmentsWithoutBridgingGaps() {
        let model = SpeedometerModel()
        let base = Date()
        model.simulateSessionStartForTesting(at: base.addingTimeInterval(-4))
        #expect(model.driveState == .active)

        let p1 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 48.1370, longitude: 11.5760),
            altitude: 520,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: 15, // 54 km/h
            timestamp: base.addingTimeInterval(-3)
        )
        let p2 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 48.1373, longitude: 11.5760),
            altitude: 522,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: 15,
            timestamp: base.addingTimeInterval(-1)
        )
        model.simulateLocationSampleForTesting(p1, receivedAt: base)
        model.simulateLocationSampleForTesting(p2, receivedAt: base)
        let distanceBeforePause = model.distanceKm
        #expect(distanceBeforePause > 0)
        #expect(model.movingTime(at: base) >= 1.9)

        model.simulatePauseForTesting(at: base)
        #expect(model.driveState == .paused)
        #expect(!model.isSessionActive)
        let elapsedAtPause = model.elapsedTime(at: base)
        #expect(abs(model.elapsedTime(at: base.addingTimeInterval(60)) - elapsedAtPause) < 0.01)
        #expect(model.pausedTime(at: base.addingTimeInterval(60)) >= 59.9)

        model.simulateResumeForTesting(at: base.addingTimeInterval(60))
        #expect(model.driveState == .active)
        #expect(model.pausedSeconds >= 59.9)

        // New point after resume must start a new route segment without adding fake jump distance
        let resumeSampleTime = Date().addingTimeInterval(0.2)
        let p3 = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 48.1400, longitude: 11.5800),
            altitude: 530,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: 12,
            timestamp: resumeSampleTime
        )
        model.simulateLocationSampleForTesting(p3, receivedAt: resumeSampleTime)
        #expect(abs(model.distanceKm - distanceBeforePause) < 0.001)
        #expect(model.routeCoordinates.last?.segmentIndex == 1)
        #expect(model.routeCoordinates.last?.speedKmh != nil)
        #expect(model.routeCoordinates.last?.altitudeMeters == 530)

        model.resetSession()
        #expect(model.driveState == .idle)
    }

    @Test func mapsNavigationManeuverInstructionsAndFormatsDistances() {
        #expect(NavigationManeuverHelper.symbol(for: "Turn left onto Main St") == "arrow.turn.up.left")
        #expect(NavigationManeuverHelper.symbol(for: "Turn right onto Oak Ave") == "arrow.turn.up.right")
        #expect(NavigationManeuverHelper.symbol(for: "Take the roundabout") == "arrow.triangle.2.circlepath")
        #expect(NavigationManeuverHelper.symbol(for: "Arrive at destination") == "flag.checkered")
        #expect(NavigationManeuverHelper.formattedDistance(1_450, usesMiles: false) == "1.5 km")
        #expect(NavigationManeuverHelper.formattedDistance(240, usesMiles: false) == "240 m")
        #expect(NavigationManeuverHelper.formattedETA(5_400) == "1h 30m")
        #expect(NavigationManeuverHelper.formattedETA(420) == "7 min")
    }

    @Test func generatesValidURLSafeSpotifyPKCEVerifierAndChallenge() {
        let verifier = SpotifyPKCE.makeCodeVerifier()
        let challenge = SpotifyPKCE.makeCodeChallenge(for: verifier)
        #expect(verifier.count >= 43)
        #expect(challenge.count == 43)
        #expect(!verifier.contains("+") && !verifier.contains("/") && !verifier.contains("="))
        #expect(!challenge.contains("+") && !challenge.contains("/") && !challenge.contains("="))
    }

    private func temporaryHistoryStorage() -> (URL, UserDefaults, String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VeluraHistory-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "VeluraTests.\(UUID().uuidString)"
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
            routeSegmentIndex: 1,
            interruptionGaps: [],
            pendingGapStartAt: nil
        )
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
