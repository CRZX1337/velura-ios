import Combine
import Foundation


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
