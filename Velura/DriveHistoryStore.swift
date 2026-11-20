import Combine
import Foundation

struct DriveRoutePoint: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let segmentIndex: Int
    let speedKmh: Double?
    let altitudeMeters: Double?
    let verticalAccuracy: Double?

    init(
        latitude: Double,
        longitude: Double,
        timestamp: Date,
        segmentIndex: Int = 0,
        speedKmh: Double? = nil,
        altitudeMeters: Double? = nil,
        verticalAccuracy: Double? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.segmentIndex = segmentIndex
        self.speedKmh = speedKmh
        self.altitudeMeters = altitudeMeters
        self.verticalAccuracy = verticalAccuracy
    }

    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case timestamp
        case segmentIndex
        case speedKmh
        case altitudeMeters
        case verticalAccuracy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        segmentIndex = try container.decodeIfPresent(Int.self, forKey: .segmentIndex) ?? 0
        speedKmh = try container.decodeIfPresent(Double.self, forKey: .speedKmh)
        altitudeMeters = try container.decodeIfPresent(Double.self, forKey: .altitudeMeters)
        verticalAccuracy = try container.decodeIfPresent(Double.self, forKey: .verticalAccuracy)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(segmentIndex, forKey: .segmentIndex)
        try container.encodeIfPresent(speedKmh, forKey: .speedKmh)
        try container.encodeIfPresent(altitudeMeters, forKey: .altitudeMeters)
        try container.encodeIfPresent(verticalAccuracy, forKey: .verticalAccuracy)
    }
}

struct DriveInterruptionGap: Codable, Equatable, Identifiable {
    let id: UUID
    let startAt: Date
    let endAt: Date

    init(id: UUID = UUID(), startAt: Date, endAt: Date) {
        self.id = id
        self.startAt = startAt
        self.endAt = endAt
    }
}

/// The complete in-memory representation used when recovering an active drive.
struct ActiveDriveSnapshot: Codable, Equatable {
    let sessionID: UUID?
    let startedAt: Date
    var elapsedSeconds: TimeInterval
    var movingSeconds: TimeInterval
    var pausedSeconds: TimeInterval
    var distanceKm: Double
    var topSpeedKmh: Double
    var routeCoordinates: [DriveRoutePoint]
    var updatedAt: Date
    var lastLocationAt: Date?
    var routeSegmentIndex: Int
    var interruptionGaps: [DriveInterruptionGap]
    var pendingGapStartAt: Date?

    init(
        sessionID: UUID?,
        startedAt: Date,
        elapsedSeconds: TimeInterval,
        movingSeconds: TimeInterval = 0,
        pausedSeconds: TimeInterval = 0,
        distanceKm: Double,
        topSpeedKmh: Double,
        routeCoordinates: [DriveRoutePoint],
        updatedAt: Date,
        lastLocationAt: Date?,
        routeSegmentIndex: Int,
        interruptionGaps: [DriveInterruptionGap],
        pendingGapStartAt: Date?
    ) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.elapsedSeconds = elapsedSeconds
        self.movingSeconds = movingSeconds
        self.pausedSeconds = pausedSeconds
        self.distanceKm = distanceKm
        self.topSpeedKmh = topSpeedKmh
        self.routeCoordinates = routeCoordinates
        self.updatedAt = updatedAt
        self.lastLocationAt = lastLocationAt
        self.routeSegmentIndex = routeSegmentIndex
        self.interruptionGaps = interruptionGaps
        self.pendingGapStartAt = pendingGapStartAt
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case startedAt
        case elapsedSeconds
        case movingSeconds
        case pausedSeconds
        case distanceKm
        case topSpeedKmh
        case routeCoordinates
        case updatedAt
        case lastLocationAt
        case routeSegmentIndex
        case interruptionGaps
        case pendingGapStartAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        elapsedSeconds = try container.decode(TimeInterval.self, forKey: .elapsedSeconds)
        movingSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .movingSeconds) ?? 0
        pausedSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .pausedSeconds) ?? 0
        distanceKm = try container.decode(Double.self, forKey: .distanceKm)
        topSpeedKmh = try container.decode(Double.self, forKey: .topSpeedKmh)
        routeCoordinates = try container.decode([DriveRoutePoint].self, forKey: .routeCoordinates)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        lastLocationAt = try container.decodeIfPresent(Date.self, forKey: .lastLocationAt)
        routeSegmentIndex = try container.decodeIfPresent(Int.self, forKey: .routeSegmentIndex)
            ?? routeCoordinates.last?.segmentIndex
            ?? 0
        interruptionGaps = try container.decodeIfPresent([DriveInterruptionGap].self, forKey: .interruptionGaps) ?? []
        pendingGapStartAt = try container.decodeIfPresent(Date.self, forKey: .pendingGapStartAt)
    }
}

/// The lightweight active-drive checkpoint. Route points live in an append-only journal.
struct ActiveDriveMetadata: Codable, Equatable {
    let sessionID: UUID?
    let startedAt: Date
    let elapsedSeconds: TimeInterval
    let movingSeconds: TimeInterval
    let pausedSeconds: TimeInterval
    let distanceKm: Double
    let topSpeedKmh: Double
    let routePointCount: Int
    let updatedAt: Date
    let lastLocationAt: Date?
    let routeSegmentIndex: Int
    let interruptionGaps: [DriveInterruptionGap]
    let pendingGapStartAt: Date?

    init(
        sessionID: UUID?,
        startedAt: Date,
        elapsedSeconds: TimeInterval,
        movingSeconds: TimeInterval = 0,
        pausedSeconds: TimeInterval = 0,
        distanceKm: Double,
        topSpeedKmh: Double,
        routePointCount: Int,
        updatedAt: Date,
        lastLocationAt: Date?,
        routeSegmentIndex: Int,
        interruptionGaps: [DriveInterruptionGap],
        pendingGapStartAt: Date?
    ) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.elapsedSeconds = elapsedSeconds
        self.movingSeconds = movingSeconds
        self.pausedSeconds = pausedSeconds
        self.distanceKm = distanceKm
        self.topSpeedKmh = topSpeedKmh
        self.routePointCount = routePointCount
        self.updatedAt = updatedAt
        self.lastLocationAt = lastLocationAt
        self.routeSegmentIndex = routeSegmentIndex
        self.interruptionGaps = interruptionGaps
        self.pendingGapStartAt = pendingGapStartAt
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case startedAt
        case elapsedSeconds
        case movingSeconds
        case pausedSeconds
        case distanceKm
        case topSpeedKmh
        case routePointCount
        case updatedAt
        case lastLocationAt
        case routeSegmentIndex
        case interruptionGaps
        case pendingGapStartAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        elapsedSeconds = try container.decode(TimeInterval.self, forKey: .elapsedSeconds)
        movingSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .movingSeconds) ?? 0
        pausedSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .pausedSeconds) ?? 0
        distanceKm = try container.decode(Double.self, forKey: .distanceKm)
        topSpeedKmh = try container.decode(Double.self, forKey: .topSpeedKmh)
        routePointCount = try container.decode(Int.self, forKey: .routePointCount)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        lastLocationAt = try container.decodeIfPresent(Date.self, forKey: .lastLocationAt)
        routeSegmentIndex = try container.decodeIfPresent(Int.self, forKey: .routeSegmentIndex) ?? 0
        interruptionGaps = try container.decodeIfPresent([DriveInterruptionGap].self, forKey: .interruptionGaps) ?? []
        pendingGapStartAt = try container.decodeIfPresent(Date.self, forKey: .pendingGapStartAt)
    }

    init(snapshot: ActiveDriveSnapshot, routePointCount: Int) {
        self.init(
            sessionID: snapshot.sessionID,
            startedAt: snapshot.startedAt,
            elapsedSeconds: snapshot.elapsedSeconds,
            movingSeconds: snapshot.movingSeconds,
            pausedSeconds: snapshot.pausedSeconds,
            distanceKm: snapshot.distanceKm,
            topSpeedKmh: snapshot.topSpeedKmh,
            routePointCount: routePointCount,
            updatedAt: snapshot.updatedAt,
            lastLocationAt: snapshot.lastLocationAt,
            routeSegmentIndex: snapshot.routeSegmentIndex,
            interruptionGaps: snapshot.interruptionGaps,
            pendingGapStartAt: snapshot.pendingGapStartAt
        )
    }

    func withRoutePointCount(_ count: Int) -> ActiveDriveMetadata {
        ActiveDriveMetadata(
            sessionID: sessionID,
            startedAt: startedAt,
            elapsedSeconds: elapsedSeconds,
            movingSeconds: movingSeconds,
            pausedSeconds: pausedSeconds,
            distanceKm: distanceKm,
            topSpeedKmh: topSpeedKmh,
            routePointCount: count,
            updatedAt: updatedAt,
            lastLocationAt: lastLocationAt,
            routeSegmentIndex: routeSegmentIndex,
            interruptionGaps: interruptionGaps,
            pendingGapStartAt: pendingGapStartAt
        )
    }

    func makeSnapshot(routeCoordinates: [DriveRoutePoint]) -> ActiveDriveSnapshot {
        ActiveDriveSnapshot(
            sessionID: sessionID,
            startedAt: startedAt,
            elapsedSeconds: elapsedSeconds,
            movingSeconds: movingSeconds,
            pausedSeconds: pausedSeconds,
            distanceKm: distanceKm,
            topSpeedKmh: topSpeedKmh,
            routeCoordinates: routeCoordinates,
            updatedAt: updatedAt,
            lastLocationAt: lastLocationAt,
            routeSegmentIndex: routeSegmentIndex,
            interruptionGaps: interruptionGaps,
            pendingGapStartAt: pendingGapStartAt
        )
    }
}

final class ActiveDriveStore {
    static let shared = ActiveDriveStore()

    private let storage: ActiveDriveFileStorage
    private let ioQueue = DispatchQueue(label: "com.velura.active-drive-storage", qos: .utility)

    init(baseDirectoryURL: URL? = nil) {
        storage = ActiveDriveFileStorage(baseDirectoryURL: baseDirectoryURL)
    }

    func load(completion: @escaping (ActiveDriveLoadResult) -> Void) {
        let storage = self.storage
        ioQueue.async {
            let result = storage.load()
            DispatchQueue.main.async { completion(result) }
        }
    }

    func save(_ metadata: ActiveDriveMetadata, completion: ((String?) -> Void)? = nil) {
        let storage = self.storage
        ioQueue.async {
            let errorMessage: String?
            do {
                try storage.save(metadata)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            DispatchQueue.main.async { completion?(errorMessage) }
        }
    }

    func appendRoutePoint(
        sessionID: UUID,
        index: Int,
        point: DriveRoutePoint,
        forceFlush: Bool = false,
        completion: ((String?) -> Void)? = nil
    ) {
        let storage = self.storage
        ioQueue.async {
            let errorMessage: String?
            do {
                try storage.appendRoutePoint(sessionID: sessionID, index: index, point: point, forceFlush: forceFlush)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            DispatchQueue.main.async { completion?(errorMessage) }
        }
    }

    func flush(completion: ((String?) -> Void)? = nil) {
        let storage = self.storage
        ioQueue.async {
            let errorMessage: String?
            do {
                try storage.flushPendingRoutePointsIfNeeded()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            DispatchQueue.main.async { completion?(errorMessage) }
        }
    }

    func clear(completion: ((String?) -> Void)? = nil) {
        let storage = self.storage
        ioQueue.async {
            let errorMessage: String?
            do {
                try storage.clear()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            DispatchQueue.main.async { completion?(errorMessage) }
        }
    }
}

struct DriveRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let duration: TimeInterval
    let movingDuration: TimeInterval?
    let pausedDuration: TimeInterval?
    let distanceKm: Double
    let topSpeedKmh: Double
    var routeCoordinates: [DriveRoutePoint]
    var interruptionGaps: [DriveInterruptionGap]

    var averageSpeedKmh: Double {
        guard duration > 0, distanceKm > 0 else { return 0 }
        return distanceKm / (duration / 3_600)
    }

    init(
        id: UUID = UUID(),
        date: Date,
        duration: TimeInterval,
        movingDuration: TimeInterval? = nil,
        pausedDuration: TimeInterval? = nil,
        distanceKm: Double,
        topSpeedKmh: Double,
        routeCoordinates: [DriveRoutePoint] = [],
        interruptionGaps: [DriveInterruptionGap] = []
    ) {
        self.id = id
        self.date = date
        self.duration = duration
        self.movingDuration = movingDuration
        self.pausedDuration = pausedDuration
        self.distanceKm = distanceKm
        self.topSpeedKmh = topSpeedKmh
        self.routeCoordinates = routeCoordinates
        self.interruptionGaps = interruptionGaps
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case duration
        case movingDuration
        case pausedDuration
        case distanceKm
        case topSpeedKmh
        case routeCoordinates
        case interruptionGaps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        movingDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .movingDuration)
        pausedDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .pausedDuration)
        distanceKm = try container.decode(Double.self, forKey: .distanceKm)
        topSpeedKmh = try container.decode(Double.self, forKey: .topSpeedKmh)
        routeCoordinates = try container.decodeIfPresent([DriveRoutePoint].self, forKey: .routeCoordinates) ?? []
        interruptionGaps = try container.decodeIfPresent([DriveInterruptionGap].self, forKey: .interruptionGaps) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(movingDuration, forKey: .movingDuration)
        try container.encodeIfPresent(pausedDuration, forKey: .pausedDuration)
        try container.encode(distanceKm, forKey: .distanceKm)
        try container.encode(topSpeedKmh, forKey: .topSpeedKmh)
        try container.encode(routeCoordinates, forKey: .routeCoordinates)
        try container.encode(interruptionGaps, forKey: .interruptionGaps)
    }
}

@MainActor
final class DriveHistoryStore: ObservableObject {
    static let shared = DriveHistoryStore()

    @Published private(set) var drives: [DriveRecord] = []
    @Published private(set) var isLoading = true
    @Published private(set) var persistenceErrorMessage: String?

    private let fileStorage = DriveHistoryFileStorage()
    private let ioQueue = DispatchQueue(label: "com.velura.drive-history-storage", qos: .utility)
    private var mutationGeneration = 0
    private var loadCompletionHandlers: [() -> Void] = []

    private init() {
        loadFromDisk()
    }

    func whenLoaded(_ completion: @escaping () -> Void) {
        if isLoading {
            loadCompletionHandlers.append(completion)
        } else {
            completion()
        }
    }

    func add(_ drive: DriveRecord, completion: ((String?) -> Void)? = nil) {
        guard !drives.contains(where: { $0.id == drive.id }) else {
            completion?(nil)
            return
        }
        drives.append(drive)
        drives.sort { $0.date > $1.date }
        enqueuePersistence({ storage in
            try storage.upsert(drive)
        }, completion: completion)
    }

    func delete(_ id: UUID) {
        guard drives.contains(where: { $0.id == id }) else { return }
        drives.removeAll { $0.id == id }
        enqueuePersistence { storage in
            try storage.delete(id)
        }
    }

    func deleteRoute(for id: UUID) {
        guard let index = drives.firstIndex(where: { $0.id == id }) else { return }
        var updatedDrive = drives[index]
        updatedDrive.routeCoordinates.removeAll()
        drives[index] = updatedDrive
        enqueuePersistence { storage in
            try storage.upsert(updatedDrive)
        }
    }

    func clear() {
        drives.removeAll()
        enqueuePersistence { storage in
            try storage.clear()
        }
    }

    func dismissPersistenceError() {
        persistenceErrorMessage = nil
    }

    private func loadFromDisk() {
        let storage = fileStorage
        let loadGeneration = mutationGeneration
        ioQueue.async { [weak self] in
            let result = storage.load()
            DispatchQueue.main.async {
                guard let self else { return }
                if self.mutationGeneration == loadGeneration {
                    self.drives = result.drives
                    self.persistenceErrorMessage = result.errorMessage
                } else if let errorMessage = result.errorMessage {
                    self.persistenceErrorMessage = errorMessage
                }
                self.isLoading = false
                let completions = self.loadCompletionHandlers
                self.loadCompletionHandlers.removeAll()
                completions.forEach { $0() }
            }
        }
    }

    private func enqueuePersistence(
        _ operation: @escaping (DriveHistoryFileStorage) throws -> Void,
        completion: ((String?) -> Void)? = nil
    ) {
        mutationGeneration += 1
        let generation = mutationGeneration
        let storage = fileStorage
        ioQueue.async { [weak self] in
            let errorMessage: String?
            let recovery: DriveHistoryLoadResult?
            do {
                try operation(storage)
                errorMessage = nil
                recovery = nil
            } catch {
                errorMessage = error.localizedDescription
                recovery = storage.load()
            }

            DispatchQueue.main.async {
                guard let self else {
                    completion?(errorMessage)
                    return
                }
                if let errorMessage, self.mutationGeneration == generation {
                    if let recovery {
                        self.drives = recovery.drives
                    }
                    let recoveryError = recovery?.errorMessage
                    self.persistenceErrorMessage = recoveryError.map {
                        "\(errorMessage) \($0)"
                    } ?? errorMessage
                }
                completion?(errorMessage)
            }
        }
    }
}
