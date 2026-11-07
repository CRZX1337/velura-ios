import Combine
import Foundation

struct DriveRoutePoint: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let segmentIndex: Int

    init(latitude: Double, longitude: Double, timestamp: Date, segmentIndex: Int = 0) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.segmentIndex = segmentIndex
    }

    private enum CodingKeys: String, CodingKey {
        case latitude
        case longitude
        case timestamp
        case segmentIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        segmentIndex = try container.decodeIfPresent(Int.self, forKey: .segmentIndex) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(segmentIndex, forKey: .segmentIndex)
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

/// A drive that has been started but not finished yet. It is written to disk
/// continuously so a suspension or termination does not lose the trip.
struct ActiveDriveSnapshot: Codable, Equatable {
    let sessionID: UUID?
    let startedAt: Date
    var elapsedSeconds: TimeInterval
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

final class ActiveDriveStore {
    static let shared = ActiveDriveStore()

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        let baseURL = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = baseURL.appendingPathComponent("Velura", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("active-drive.json")
    }

    func load() -> ActiveDriveSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(ActiveDriveSnapshot.self, from: data)
    }

    func save(_ snapshot: ActiveDriveSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

struct DriveRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let duration: TimeInterval
    let distanceKm: Double
    let topSpeedKmh: Double
    var routeCoordinates: [DriveRoutePoint]
    var interruptionGaps: [DriveInterruptionGap]

    init(
        id: UUID = UUID(),
        date: Date,
        duration: TimeInterval,
        distanceKm: Double,
        topSpeedKmh: Double,
        routeCoordinates: [DriveRoutePoint] = [],
        interruptionGaps: [DriveInterruptionGap] = []
    ) {
        self.id = id
        self.date = date
        self.duration = duration
        self.distanceKm = distanceKm
        self.topSpeedKmh = topSpeedKmh
        self.routeCoordinates = routeCoordinates
        self.interruptionGaps = interruptionGaps
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case duration
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

    private let storageKey = "velura.driveHistory"
    private let defaults = UserDefaults.standard

    private init() {
        if let data = defaults.data(forKey: storageKey),
           let storedDrives = try? JSONDecoder().decode([DriveRecord].self, from: data) {
            drives = storedDrives.sorted { $0.date > $1.date }
        }
    }

    func add(_ drive: DriveRecord) {
        guard !drives.contains(where: { $0.id == drive.id }) else { return }
        drives.append(drive)
        drives.sort { $0.date > $1.date }
        persist()
    }

    func delete(_ id: UUID) {
        drives.removeAll { $0.id == id }
        persist()
    }

    func deleteRoute(for id: UUID) {
        guard let index = drives.firstIndex(where: { $0.id == id }) else { return }
        drives[index].routeCoordinates.removeAll()
        persist()
    }

    func clear() {
        drives.removeAll()
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(drives) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
