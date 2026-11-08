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
        let sample = location(latitude: 37, longitude: -121.9999, accuracy: 5, speed: 5, at: timestamp.addingTimeInterval(2))

        #expect(filter.issue(for: sample, receivedAt: sample.timestamp, previousLocation: previous) == nil)
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
