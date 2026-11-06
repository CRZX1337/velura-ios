import Combine
import Foundation

struct DriveRoutePoint: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
}

struct DriveRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let duration: TimeInterval
    let distanceKm: Double
    let topSpeedKmh: Double
    var routeCoordinates: [DriveRoutePoint]

    init(
        id: UUID = UUID(),
        date: Date,
        duration: TimeInterval,
        distanceKm: Double,
        topSpeedKmh: Double,
        routeCoordinates: [DriveRoutePoint] = []
    ) {
        self.id = id
        self.date = date
        self.duration = duration
        self.distanceKm = distanceKm
        self.topSpeedKmh = topSpeedKmh
        self.routeCoordinates = routeCoordinates
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case date
        case duration
        case distanceKm
        case topSpeedKmh
        case routeCoordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        date = try container.decode(Date.self, forKey: .date)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        distanceKm = try container.decode(Double.self, forKey: .distanceKm)
        topSpeedKmh = try container.decode(Double.self, forKey: .topSpeedKmh)
        routeCoordinates = try container.decodeIfPresent([DriveRoutePoint].self, forKey: .routeCoordinates) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(duration, forKey: .duration)
        try container.encode(distanceKm, forKey: .distanceKm)
        try container.encode(topSpeedKmh, forKey: .topSpeedKmh)
        try container.encode(routeCoordinates, forKey: .routeCoordinates)
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
