import Foundation

private enum DriveFileStorageError: LocalizedError {
    case storageDirectoryUnavailable
    case unsupportedHistoryVersion(Int)
    case unsupportedActiveDriveVersion(Int)
    case invalidRouteJournal
    case driveRecordIDMismatch
    case routeCheckpointMismatch(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .storageDirectoryUnavailable:
            "The app's drive storage directory is unavailable."
        case .unsupportedHistoryVersion(let version):
            "A saved drive uses an unsupported storage version (\(version))."
        case .unsupportedActiveDriveVersion(let version):
            "The active drive uses an unsupported storage version (\(version))."
        case .invalidRouteJournal:
            "The active route checkpoint is incomplete or unreadable."
        case .driveRecordIDMismatch:
            "A saved drive file does not match its record identifier."
        case .routeCheckpointMismatch(let expected, let actual):
            "The active route checkpoint is incomplete (expected \(expected) points, found \(actual))."
        }
    }
}

struct DriveHistoryLoadResult {
    let drives: [DriveRecord]
    let errorMessage: String?
}

private struct VersionedDriveRecord: Codable {
    let schemaVersion: Int
    let record: DriveRecord
}

final class DriveHistoryFileStorage {
    static let legacyStorageKey = "velura.driveHistory"

    private let defaults: UserDefaults
    private let fileManager: FileManager
    private let baseDirectoryURL: URL?
    private let baseDirectoryError: Error?

    var recordsDirectoryURL: URL? {
        baseDirectoryURL?.appendingPathComponent("DriveHistory-v1", isDirectory: true)
    }

    init(
        baseDirectoryURL: URL? = nil,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        self.defaults = defaults
        self.fileManager = fileManager

        if let baseDirectoryURL {
            self.baseDirectoryURL = baseDirectoryURL
            baseDirectoryError = nil
        } else {
            do {
                let applicationSupport = try fileManager.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                self.baseDirectoryURL = applicationSupport.appendingPathComponent("Velura", isDirectory: true)
                baseDirectoryError = nil
            } catch {
                self.baseDirectoryURL = nil
                baseDirectoryError = error
            }
        }
    }

    func load() -> DriveHistoryLoadResult {
        do {
            try migrateLegacyHistoryIfNeeded()
            return readVersionedRecords()
        } catch {
            let legacyDrives = defaults.data(forKey: Self.legacyStorageKey)
                .flatMap { try? JSONDecoder().decode([DriveRecord].self, from: $0) }
            let storedDrives = readVersionedRecords()
            return DriveHistoryLoadResult(
                drives: (legacyDrives ?? storedDrives.drives).sorted { $0.date > $1.date },
                errorMessage: storageErrorMessage(error, additional: storedDrives.errorMessage)
            )
        }
    }

    func upsert(_ drive: DriveRecord) throws {
        try migrateLegacyHistoryIfNeeded()
        try writeVersionedRecord(drive)
        let directoryURL = try requiredRecordsDirectory(create: false)
        for backupDirectory in try clearingBackupDirectories(in: directoryURL.deletingLastPathComponent()) {
            let backupFileURL = backupDirectory.appendingPathComponent("\(drive.id.uuidString).json")
            if fileManager.fileExists(atPath: backupFileURL.path) {
                try fileManager.removeItem(at: backupFileURL)
            }
        }
    }

    func delete(_ id: UUID) throws {
        try migrateLegacyHistoryIfNeeded()
        let directoryURL = try requiredRecordsDirectory(create: false)
        var directories: [URL] = []
        if fileManager.fileExists(atPath: directoryURL.path) {
            directories.append(directoryURL)
        }
        directories.append(contentsOf: try clearingBackupDirectories(in: directoryURL.deletingLastPathComponent()))

        for directory in directories {
            let fileURL = directory.appendingPathComponent("\(id.uuidString).json")
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        }
    }

    func clear() throws {
        let directoryURL = try requiredRecordsDirectory(create: false)
        let parentURL = directoryURL.deletingLastPathComponent()
        let oldBackups = try clearingBackupDirectories(in: parentURL)
        var stagedBackupURL: URL?

        if fileManager.fileExists(atPath: directoryURL.path) {
            let backupURL = parentURL.appendingPathComponent(
                "DriveHistory-clearing-\(UUID().uuidString)",
                isDirectory: true
            )
            try fileManager.moveItem(at: directoryURL, to: backupURL)
            stagedBackupURL = backupURL
        }

        do {
            for backupURL in oldBackups {
                try fileManager.removeItem(at: backupURL)
            }
            if let stagedBackupURL {
                try fileManager.removeItem(at: stagedBackupURL)
            }
            defaults.removeObject(forKey: Self.legacyStorageKey)
        } catch {
            if let stagedBackupURL,
               fileManager.fileExists(atPath: stagedBackupURL.path),
               !fileManager.fileExists(atPath: directoryURL.path) {
                try? fileManager.moveItem(at: stagedBackupURL, to: directoryURL)
            }
            throw error
        }
    }

    func recordFileURL(for id: UUID) -> URL? {
        recordsDirectoryURL?.appendingPathComponent("\(id.uuidString).json")
    }

    private func migrateLegacyHistoryIfNeeded() throws {
        guard let legacyData = defaults.data(forKey: Self.legacyStorageKey) else { return }
        let legacyDrives = try JSONDecoder().decode([DriveRecord].self, from: legacyData)
        _ = try requiredRecordsDirectory(create: true)

        // Keep the original UserDefaults value until every versioned drive file is written.
        for drive in legacyDrives {
            try writeVersionedRecord(drive)
        }
        defaults.removeObject(forKey: Self.legacyStorageKey)
    }

    private func readVersionedRecords() -> DriveHistoryLoadResult {
        do {
            let directoryURL = try requiredRecordsDirectory(create: false)
            let parentURL = directoryURL.deletingLastPathComponent()
            var directories: [URL] = []
            if fileManager.fileExists(atPath: directoryURL.path) {
                directories.append(directoryURL)
            }
            directories.append(contentsOf: try clearingBackupDirectories(in: parentURL))
            guard !directories.isEmpty else {
                return DriveHistoryLoadResult(drives: [], errorMessage: nil)
            }

            var drivesByID: [UUID: DriveRecord] = [:]
            var firstError: String?

            for directory in directories {
                let files = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                for fileURL in files where fileURL.pathExtension == "json" {
                    do {
                        let data = try Data(contentsOf: fileURL)
                        let stored = try JSONDecoder().decode(VersionedDriveRecord.self, from: data)
                        guard stored.schemaVersion == 1 else {
                            throw DriveFileStorageError.unsupportedHistoryVersion(stored.schemaVersion)
                        }
                        guard fileURL.deletingPathExtension().lastPathComponent == stored.record.id.uuidString else {
                            throw DriveFileStorageError.driveRecordIDMismatch
                        }
                        if drivesByID[stored.record.id] == nil {
                            drivesByID[stored.record.id] = stored.record
                        }
                    } catch {
                        if firstError == nil {
                            firstError = "A saved drive could not be read. \(error.localizedDescription)"
                        }
                    }
                }
            }

            return DriveHistoryLoadResult(
                drives: drivesByID.values.sorted { $0.date > $1.date },
                errorMessage: firstError
            )
        } catch {
            return DriveHistoryLoadResult(drives: [], errorMessage: error.localizedDescription)
        }
    }

    private func writeVersionedRecord(_ drive: DriveRecord) throws {
        let fileURL = try requiredRecordFileURL(for: drive.id)
        let data = try JSONEncoder().encode(VersionedDriveRecord(schemaVersion: 1, record: drive))
        try data.write(to: fileURL, options: .atomic)
    }

    private func requiredRecordFileURL(for id: UUID) throws -> URL {
        try requiredRecordsDirectory(create: true).appendingPathComponent("\(id.uuidString).json")
    }

    private func requiredRecordsDirectory(create: Bool) throws -> URL {
        guard let baseDirectoryURL else {
            throw baseDirectoryError ?? DriveFileStorageError.storageDirectoryUnavailable
        }
        let directoryURL = baseDirectoryURL.appendingPathComponent("DriveHistory-v1", isDirectory: true)
        if create {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL
    }

    private func clearingBackupDirectories(in parentURL: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: parentURL.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: parentURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            guard url.lastPathComponent.hasPrefix("DriveHistory-clearing-"),
                  let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory else {
                return false
            }
            return isDirectory
        }
    }

    private func storageErrorMessage(_ error: Error, additional: String?) -> String {
        if let additional, additional != error.localizedDescription {
            return "\(error.localizedDescription) \(additional)"
        }
        return error.localizedDescription
    }
}

struct ActiveDriveLoadResult {
    let snapshot: ActiveDriveSnapshot?
    let errorMessage: String?
}

private struct VersionedActiveDriveMetadata: Codable {
    let schemaVersion: Int
    let metadata: ActiveDriveMetadata
}

private struct VersionedActiveDriveRouteEntry: Codable {
    let schemaVersion: Int
    let index: Int
    let point: DriveRoutePoint
}

final class ActiveDriveFileStorage {
    private let fileManager: FileManager
    private let baseDirectoryURL: URL?
    private let baseDirectoryError: Error?
    private var activeSessionID: UUID?
    private var persistedRoutePointCount = 0
    private var pendingRoutePoints: [Int: DriveRoutePoint] = [:]
    private var routeJournalWritable = true

    init(baseDirectoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager

        if let baseDirectoryURL {
            self.baseDirectoryURL = baseDirectoryURL
            baseDirectoryError = nil
        } else {
            do {
                let applicationSupport = try fileManager.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                self.baseDirectoryURL = applicationSupport.appendingPathComponent("Velura", isDirectory: true)
                baseDirectoryError = nil
            } catch {
                self.baseDirectoryURL = nil
                baseDirectoryError = error
            }
        }
    }

    func load() -> ActiveDriveLoadResult {
        do {
            let paths = try storagePaths(create: false)
            try restoreClearingBackupIfNeeded(paths: paths)

            if fileManager.fileExists(atPath: paths.legacySnapshot.path) {
                let data = try Data(contentsOf: paths.legacySnapshot)
                let legacySnapshot = try JSONDecoder().decode(ActiveDriveSnapshot.self, from: data)
                if fileManager.fileExists(atPath: paths.metadata.path) {
                    let current = loadVersionedSnapshot(paths: paths)
                    guard let currentSnapshot = current.snapshot else { return current }
                    do {
                        try fileManager.removeItem(at: paths.legacySnapshot)
                        return current
                    } catch {
                        let messages = [current.errorMessage, error.localizedDescription]
                            .compactMap { $0 }
                            .joined(separator: " ")
                        return ActiveDriveLoadResult(snapshot: currentSnapshot, errorMessage: messages)
                    }
                }

                do {
                    try migrateLegacySnapshot(legacySnapshot, paths: paths)
                    try fileManager.removeItem(at: paths.legacySnapshot)
                    return ActiveDriveLoadResult(snapshot: legacySnapshot, errorMessage: nil)
                } catch {
                    return ActiveDriveLoadResult(snapshot: legacySnapshot, errorMessage: error.localizedDescription)
                }
            }

            return loadVersionedSnapshot(paths: paths)
        } catch {
            return ActiveDriveLoadResult(snapshot: nil, errorMessage: error.localizedDescription)
        }
    }

    private func loadVersionedSnapshot(paths: StoragePaths) -> ActiveDriveLoadResult {
        activeSessionID = nil
        persistedRoutePointCount = 0
        pendingRoutePoints.removeAll()
        routeJournalWritable = true

        guard fileManager.fileExists(atPath: paths.metadata.path) else {
            let orphanedRouteExists = fileManager.fileExists(atPath: paths.routeJournal.path)
            return ActiveDriveLoadResult(
                snapshot: nil,
                errorMessage: orphanedRouteExists ? DriveFileStorageError.invalidRouteJournal.localizedDescription : nil
            )
        }

        do {
            let data = try Data(contentsOf: paths.metadata)
            let stored = try JSONDecoder().decode(VersionedActiveDriveMetadata.self, from: data)
            guard stored.schemaVersion == 1 else {
                throw DriveFileStorageError.unsupportedActiveDriveVersion(stored.schemaVersion)
            }
            guard stored.metadata.routePointCount >= 0 else {
                throw DriveFileStorageError.invalidRouteJournal
            }

            let route = readRouteJournal(
                at: paths.routeJournal,
                expectedPointCount: stored.metadata.routePointCount
            )
            activeSessionID = stored.metadata.sessionID
            persistedRoutePointCount = route.points.count
            routeJournalWritable = route.isWritable
            let snapshot = stored.metadata.makeSnapshot(routeCoordinates: route.points)
            return ActiveDriveLoadResult(snapshot: snapshot, errorMessage: route.errorMessage)
        } catch {
            return ActiveDriveLoadResult(snapshot: nil, errorMessage: error.localizedDescription)
        }
    }

    private func restoreClearingBackupIfNeeded(paths: StoragePaths) throws {
        guard !fileManager.fileExists(atPath: paths.metadata.path) else { return }
        let backups = try activeDriveClearingBackupDirectories(in: paths.baseDirectory)
        guard let backup = backups.first(where: {
            fileManager.fileExists(atPath: $0.appendingPathComponent("metadata.json").path)
        }) else { return }

        var orphanedDirectory: URL?
        if fileManager.fileExists(atPath: paths.versionedDirectory.path) {
            let orphan = paths.baseDirectory.appendingPathComponent(
                "ActiveDrive-orphaned-\(UUID().uuidString)",
                isDirectory: true
            )
            try fileManager.moveItem(at: paths.versionedDirectory, to: orphan)
            orphanedDirectory = orphan
        }

        do {
            try fileManager.moveItem(at: backup, to: paths.versionedDirectory)
        } catch {
            if let orphanedDirectory, !fileManager.fileExists(atPath: paths.versionedDirectory.path) {
                try? fileManager.moveItem(at: orphanedDirectory, to: paths.versionedDirectory)
            }
            throw error
        }
    }

    func save(_ metadata: ActiveDriveMetadata) throws {
        let paths = try storagePaths(create: true)
        try ensureLegacySnapshotMigrated(paths: paths)
        try prepareSession(metadata.sessionID, paths: paths)
        guard routeJournalWritable else { throw DriveFileStorageError.invalidRouteJournal }
        try flushPendingRoutePoints(at: paths.routeJournal)
        guard metadata.routePointCount == persistedRoutePointCount else {
            throw DriveFileStorageError.routeCheckpointMismatch(
                expected: metadata.routePointCount,
                actual: persistedRoutePointCount
            )
        }

        let storedMetadata = metadata.withRoutePointCount(persistedRoutePointCount)
        let data = try JSONEncoder().encode(VersionedActiveDriveMetadata(schemaVersion: 1, metadata: storedMetadata))
        try data.write(to: paths.metadata, options: .atomic)
    }

    func appendRoutePoint(sessionID: UUID, index: Int, point: DriveRoutePoint) throws {
        let paths = try storagePaths(create: true)
        try ensureLegacySnapshotMigrated(paths: paths)
        try prepareSession(sessionID, paths: paths)
        guard routeJournalWritable, index >= 0 else { throw DriveFileStorageError.invalidRouteJournal }
        guard index >= persistedRoutePointCount else { return }
        pendingRoutePoints[index] = point
        try flushPendingRoutePoints(at: paths.routeJournal)
    }

    func clear() throws {
        let paths = try storagePaths(create: false)
        let oldBackups = try activeDriveClearingBackupDirectories(in: paths.baseDirectory)
        var stagedBackupURL: URL?

        if fileManager.fileExists(atPath: paths.versionedDirectory.path) {
            let backupURL = paths.baseDirectory.appendingPathComponent(
                "ActiveDrive-clearing-\(UUID().uuidString)",
                isDirectory: true
            )
            try fileManager.moveItem(at: paths.versionedDirectory, to: backupURL)
            stagedBackupURL = backupURL
        }

        do {
            for backupURL in oldBackups {
                try fileManager.removeItem(at: backupURL)
            }
            if let stagedBackupURL {
                try fileManager.removeItem(at: stagedBackupURL)
            }
            if fileManager.fileExists(atPath: paths.legacySnapshot.path) {
                try fileManager.removeItem(at: paths.legacySnapshot)
            }
        } catch {
            if let stagedBackupURL,
               fileManager.fileExists(atPath: stagedBackupURL.path),
               !fileManager.fileExists(atPath: paths.versionedDirectory.path) {
                try? fileManager.moveItem(at: stagedBackupURL, to: paths.versionedDirectory)
            }
            throw error
        }

        activeSessionID = nil
        persistedRoutePointCount = 0
        pendingRoutePoints.removeAll()
        routeJournalWritable = true
    }

    private func ensureLegacySnapshotMigrated(paths: StoragePaths) throws {
        guard !fileManager.fileExists(atPath: paths.metadata.path),
              fileManager.fileExists(atPath: paths.legacySnapshot.path) else { return }
        let data = try Data(contentsOf: paths.legacySnapshot)
        let snapshot = try JSONDecoder().decode(ActiveDriveSnapshot.self, from: data)
        try migrateLegacySnapshot(snapshot, paths: paths)
    }

    private func migrateLegacySnapshot(_ snapshot: ActiveDriveSnapshot, paths: StoragePaths) throws {
        try fileManager.createDirectory(at: paths.versionedDirectory, withIntermediateDirectories: true)
        try writeRouteJournal(snapshot.routeCoordinates, to: paths.routeJournal)
        let metadata = ActiveDriveMetadata(snapshot: snapshot, routePointCount: snapshot.routeCoordinates.count)
        let data = try JSONEncoder().encode(VersionedActiveDriveMetadata(schemaVersion: 1, metadata: metadata))
        try data.write(to: paths.metadata, options: .atomic)
        activeSessionID = snapshot.sessionID
        persistedRoutePointCount = snapshot.routeCoordinates.count
        pendingRoutePoints.removeAll()
        routeJournalWritable = true
    }

    private func prepareSession(_ sessionID: UUID?, paths: StoragePaths) throws {
        guard activeSessionID != sessionID else {
            try fileManager.createDirectory(at: paths.versionedDirectory, withIntermediateDirectories: true)
            return
        }

        // A pre-versioned snapshot may not have a session id. Adopt the id assigned
        // during recovery without discarding its already migrated route points.
        if activeSessionID == nil, persistedRoutePointCount > 0 {
            activeSessionID = sessionID
            try fileManager.createDirectory(at: paths.versionedDirectory, withIntermediateDirectories: true)
            return
        }

        if fileManager.fileExists(atPath: paths.versionedDirectory.path) {
            try fileManager.removeItem(at: paths.versionedDirectory)
        }
        try fileManager.createDirectory(at: paths.versionedDirectory, withIntermediateDirectories: true)
        activeSessionID = sessionID
        persistedRoutePointCount = 0
        pendingRoutePoints.removeAll()
        routeJournalWritable = true
    }

    private func flushPendingRoutePoints(at routeJournalURL: URL) throws {
        while let point = pendingRoutePoints[persistedRoutePointCount] {
            try appendRouteEntry(
                VersionedActiveDriveRouteEntry(schemaVersion: 1, index: persistedRoutePointCount, point: point),
                to: routeJournalURL
            )
            pendingRoutePoints.removeValue(forKey: persistedRoutePointCount)
            persistedRoutePointCount += 1
        }
    }

    private func appendRouteEntry(_ entry: VersionedActiveDriveRouteEntry, to url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try Data().write(to: url, options: .atomic)
        }
        var line = try JSONEncoder().encode(entry)
        line.append(0x0A)
        let fileHandle = try FileHandle(forWritingTo: url)
        defer { try? fileHandle.close() }
        try fileHandle.seekToEnd()
        try fileHandle.write(contentsOf: line)
        try fileHandle.synchronize()
    }

    private func writeRouteJournal(_ points: [DriveRoutePoint], to url: URL) throws {
        var data = Data()
        for (index, point) in points.enumerated() {
            var line = try JSONEncoder().encode(
                VersionedActiveDriveRouteEntry(schemaVersion: 1, index: index, point: point)
            )
            line.append(0x0A)
            data.append(line)
        }
        try data.write(to: url, options: .atomic)
    }

    private func readRouteJournal(
        at url: URL,
        expectedPointCount: Int
    ) -> (points: [DriveRoutePoint], errorMessage: String?, isWritable: Bool) {
        guard fileManager.fileExists(atPath: url.path) else {
            return expectedPointCount == 0
                ? ([], nil, true)
                : (
                    [],
                    DriveFileStorageError.routeCheckpointMismatch(expected: expectedPointCount, actual: 0).localizedDescription,
                    true
                )
        }

        do {
            let data = try Data(contentsOf: url)
            var points: [DriveRoutePoint] = []
            var errorMessage: String?
            var needsRepair = !data.isEmpty && data.last != 0x0A

            for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
                do {
                    let entry = try JSONDecoder().decode(VersionedActiveDriveRouteEntry.self, from: Data(line))
                    guard entry.schemaVersion == 1 else {
                        throw DriveFileStorageError.unsupportedActiveDriveVersion(entry.schemaVersion)
                    }
                    if entry.index < points.count {
                        guard points[entry.index] == entry.point else {
                            throw DriveFileStorageError.invalidRouteJournal
                        }
                        continue
                    }
                    guard entry.index == points.count else {
                        throw DriveFileStorageError.invalidRouteJournal
                    }
                    points.append(entry.point)
                } catch {
                    errorMessage = error.localizedDescription
                    needsRepair = true
                    break
                }
            }

            if errorMessage == nil, points.count < expectedPointCount {
                errorMessage = DriveFileStorageError.routeCheckpointMismatch(
                    expected: expectedPointCount,
                    actual: points.count
                ).localizedDescription
            }

            var isWritable = true
            if needsRepair {
                do {
                    try writeRouteJournal(points, to: url)
                } catch {
                    isWritable = false
                    errorMessage = [errorMessage, error.localizedDescription]
                        .compactMap { $0 }
                        .joined(separator: " ")
                }
            }
            return (points, errorMessage, isWritable)
        } catch {
            return ([], error.localizedDescription, false)
        }
    }

    private func activeDriveClearingBackupDirectories(in baseURL: URL) throws -> [URL] {
        guard fileManager.fileExists(atPath: baseURL.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            guard url.lastPathComponent.hasPrefix("ActiveDrive-clearing-"),
                  let isDirectory = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory else {
                return false
            }
            return isDirectory
        }
    }

    private func storagePaths(create: Bool) throws -> StoragePaths {
        guard let baseDirectoryURL else {
            throw baseDirectoryError ?? DriveFileStorageError.storageDirectoryUnavailable
        }
        if create {
            try fileManager.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
        }
        let versionedDirectory = baseDirectoryURL.appendingPathComponent("ActiveDrive-v1", isDirectory: true)
        if create {
            try fileManager.createDirectory(at: versionedDirectory, withIntermediateDirectories: true)
        }
        return StoragePaths(
            baseDirectory: baseDirectoryURL,
            legacySnapshot: baseDirectoryURL.appendingPathComponent("active-drive.json"),
            versionedDirectory: versionedDirectory,
            metadata: versionedDirectory.appendingPathComponent("metadata.json"),
            routeJournal: versionedDirectory.appendingPathComponent("route.jsonl")
        )
    }

    private struct StoragePaths {
        let baseDirectory: URL
        let legacySnapshot: URL
        let versionedDirectory: URL
        let metadata: URL
        let routeJournal: URL
    }
}

