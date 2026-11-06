import CoreLocation
import Foundation
import UIKit

enum AccelerationTestState: Equatable {
    case ready
    case waitingForMovement
    case timing
    case completed
}

struct AccelerationAttempt: Codable, Equatable, Identifiable {
    let id: UUID
    let targetKmh: Int
    let duration: TimeInterval
    let date: Date

    init(id: UUID = UUID(), targetKmh: Int, duration: TimeInterval, date: Date) {
        self.id = id
        self.targetKmh = targetKmh
        self.duration = duration
        self.date = date
    }
}

struct AccelerationAttemptGroup: Identifiable {
    let targetKmh: Int
    let attempts: [AccelerationAttempt]

    var id: Int { targetKmh }
    var bestTime: TimeInterval? { attempts.map(\.duration).min() }
}

@MainActor
final class SpeedometerModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var speedKmh = 0.0
    @Published private(set) var topSpeedKmh = 0.0
    @Published private(set) var distanceKm = 0.0
    @Published private(set) var elapsedSeconds = 0.0
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var horizontalAccuracy: CLLocationAccuracy = -1
    @Published private(set) var hasGPSFix = false
    @Published private(set) var isSessionActive = false
    @Published private(set) var isOverspeedWarningActive = false
    @Published private(set) var hasUnfinishedSession = false
    @Published private(set) var accelerationPreset = 50
    @Published private(set) var customAccelerationTargetKmh = 80
    @Published private(set) var accelerationTargetKmh = 50.0
    @Published private(set) var accelerationState: AccelerationTestState = .ready
    @Published private(set) var accelerationResult: TimeInterval?
    @Published private(set) var bestAccelerationTime: TimeInterval?
    @Published private(set) var accelerationAttempts: [AccelerationAttempt] = []
    @Published private(set) var isNewAccelerationBest = false
    @Published var showLocationAlert = false

    private let locationManager = CLLocationManager()
    private let defaults = UserDefaults.standard
    private let accelerationAttemptsStorageKey = "speedometer.acceleration.attempts"
    private var previousLocation: CLLocation?
    private var lastValidLocation: CLLocation?
    private var routeCoordinates: [DriveRoutePoint] = []
    private var sessionStartedAt: Date?
    private var driveStartedAt: Date?
    private var accelerationRunStartedAt: Date?
    @Published private(set) var canBeginAccelerationRun = false
    private var pendingAccelerationArm = false
    private var pendingSessionStart = false
    private let accelerationStartThresholdKmh = 2.0
    private var overspeedWarningEnabled = false
    private var overspeedThresholdKmh = 100.0

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 2
        locationManager.activityType = .automotiveNavigation
        locationManager.pausesLocationUpdatesAutomatically = true
        restoreAccelerationSettings()
    }

    var gpsStatusTitle: String {
        if hasGPSFix { return "GPS LOCKED" }
        switch authorizationStatus {
        case .denied, .restricted:
            return "LOCATION OFF"
        case .notDetermined:
            return "GPS STANDBY"
        case .authorizedAlways, .authorizedWhenInUse:
            return isSessionActive ? "SEARCHING FOR GPS" : "GPS READY"
        @unknown default:
            return "GPS STANDBY"
        }
    }

    var gpsStatusDetail: String {
        if hasGPSFix { return "Accuracy ±\(Int(horizontalAccuracy.rounded())) m" }
        switch authorizationStatus {
        case .denied, .restricted:
            return "Allow location access in Settings"
        case .notDetermined:
            return "Start a session to connect GPS"
        case .authorizedAlways, .authorizedWhenInUse:
            return isSessionActive ? "Waiting for a clear satellite fix" : "Ready when you are"
        @unknown default:
            return "Waiting for location permission"
        }
    }

    func elapsedTime(at date: Date = .now) -> TimeInterval {
        elapsedSeconds + (sessionStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    func configureOverspeedWarning(enabled: Bool, thresholdKmh: Double) {
        overspeedWarningEnabled = enabled
        overspeedThresholdKmh = max(1, thresholdKmh)
        updateOverspeedWarning(triggerHaptic: false)
    }

    func startSession() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            pendingSessionStart = true
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            pendingAccelerationArm = false
            accelerationState = .ready
            showLocationAlert = true
        case .authorizedAlways, .authorizedWhenInUse:
            beginSession()
        @unknown default:
            pendingAccelerationArm = false
            accelerationState = .ready
            showLocationAlert = true
        }
    }

    func selectAccelerationPreset(_ preset: Int) {
        guard [20, 50, 100].contains(preset) else { return }
        accelerationPreset = preset
        accelerationTargetKmh = Double(preset)
        defaults.set(preset, forKey: "speedometer.acceleration.preset")
        resetAccelerationTest()
        loadBestAccelerationTime()
    }

    func selectCustomAccelerationTarget(_ targetKmh: Double) {
        let target = min(max(Int((targetKmh / 5).rounded()) * 5, 20), 240)
        customAccelerationTargetKmh = target
        accelerationPreset = -1
        accelerationTargetKmh = Double(target)
        defaults.set(-1, forKey: "speedometer.acceleration.preset")
        defaults.set(target, forKey: "speedometer.acceleration.customTarget")
        resetAccelerationTest()
        loadBestAccelerationTime()
    }

    func startAccelerationTest() {
        guard accelerationState != .waitingForMovement && accelerationState != .timing else { return }
        accelerationResult = nil
        isNewAccelerationBest = false
        accelerationRunStartedAt = nil
        accelerationState = .waitingForMovement
        canBeginAccelerationRun = speedKmh < accelerationStartThresholdKmh

        guard isSessionActive else {
            pendingAccelerationArm = true
            startSession()
            return
        }
    }

    func resetAccelerationTest() {
        pendingAccelerationArm = false
        canBeginAccelerationRun = false
        accelerationRunStartedAt = nil
        accelerationResult = nil
        isNewAccelerationBest = false
        accelerationState = .ready
    }

    func accelerationElapsed(at date: Date = .now) -> TimeInterval {
        if accelerationState == .timing, let accelerationRunStartedAt {
            return max(0, date.timeIntervalSince(accelerationRunStartedAt))
        }
        return accelerationResult ?? 0
    }

    var accelerationAttemptGroups: [AccelerationAttemptGroup] {
        let groupedAttempts = Dictionary(grouping: accelerationAttempts, by: \.targetKmh)
        return groupedAttempts.map { entry in
            AccelerationAttemptGroup(
                targetKmh: entry.key,
                attempts: entry.value.sorted { $0.date > $1.date }
            )
        }
        .sorted { $0.targetKmh < $1.targetKmh }
    }

    func deleteAccelerationAttempt(_ id: UUID) {
        guard let attempt = accelerationAttempts.first(where: { $0.id == id }) else { return }
        accelerationAttempts.removeAll { $0.id == id }
        persistAccelerationAttempts()

        let targetKey = "speedometer.acceleration.best.\(attempt.targetKmh)"
        let remainingBest = accelerationAttempts
            .filter { $0.targetKmh == attempt.targetKmh }
            .map(\.duration)
            .min()
        if let remainingBest {
            defaults.set(remainingBest, forKey: targetKey)
        } else {
            defaults.removeObject(forKey: targetKey)
        }

        if Int(accelerationTargetKmh.rounded()) == attempt.targetKmh {
            bestAccelerationTime = remainingBest
        }
    }

    func pauseSession() {
        guard isSessionActive else { return }
        if let sessionStartedAt {
            elapsedSeconds += max(0, Date().timeIntervalSince(sessionStartedAt))
        }
        sessionStartedAt = nil
        isSessionActive = false
        hasGPSFix = false
        speedKmh = 0
        updateOverspeedWarning(triggerHaptic: false)
        previousLocation = nil
        if accelerationState == .waitingForMovement || accelerationState == .timing {
            resetAccelerationTest()
        }
        locationManager.stopUpdatingLocation()
    }

    func finishSession() {
        guard hasUnfinishedSession else { return }
        if isSessionActive {
            locationManager.stopUpdatingLocation()
        }

        if let lastValidLocation {
            recordRoutePoint(lastValidLocation, force: true)
        }
        let duration = elapsedTime(at: .now)
        if duration > 0 {
            DriveHistoryStore.shared.add(DriveRecord(
                date: driveStartedAt ?? .now,
                duration: duration,
                distanceKm: distanceKm,
                topSpeedKmh: topSpeedKmh,
                routeCoordinates: routeCoordinates.count >= 2 ? routeCoordinates : []
            ))
        }
        resetSession()
    }

    func resetSession() {
        if isSessionActive {
            locationManager.stopUpdatingLocation()
        }
        pendingSessionStart = false
        isSessionActive = false
        hasUnfinishedSession = false
        if accelerationState == .waitingForMovement || accelerationState == .timing {
            resetAccelerationTest()
        }
        sessionStartedAt = nil
        driveStartedAt = nil
        previousLocation = nil
        lastValidLocation = nil
        routeCoordinates.removeAll()
        speedKmh = 0
        topSpeedKmh = 0
        distanceKm = 0
        elapsedSeconds = 0
        horizontalAccuracy = -1
        hasGPSFix = false
        updateOverspeedWarning(triggerHaptic: false)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if pendingSessionStart {
            switch authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                pendingSessionStart = false
                beginSession()
            case .denied, .restricted:
                pendingSessionStart = false
                pendingAccelerationArm = false
                accelerationState = .ready
                showLocationAlert = true
            default:
                break
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isSessionActive else { return }
        for location in locations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 50 {
            horizontalAccuracy = location.horizontalAccuracy
            hasGPSFix = true
            lastValidLocation = location
            recordRoutePoint(location)

            if location.speed >= 0 {
                let measuredSpeed = max(0, location.speed * 3.6)
                speedKmh = measuredSpeed < 1.0 ? 0 : measuredSpeed
                topSpeedKmh = max(topSpeedKmh, speedKmh)
                updateAccelerationTest(speedKmh: speedKmh, at: location.timestamp)
                updateOverspeedWarning(triggerHaptic: true)
            }

            if let previousLocation {
                let distance = location.distance(from: previousLocation)
                let timeDelta = location.timestamp.timeIntervalSince(previousLocation.timestamp)
                if distance < 150 && timeDelta > 0 && timeDelta < 30 {
                    distanceKm += distance / 1_000
                }
            }
            previousLocation = location
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        hasGPSFix = false
        updateOverspeedWarning(triggerHaptic: false)
    }

    private func updateOverspeedWarning(triggerHaptic: Bool) {
        let shouldWarn = isSessionActive && hasGPSFix && overspeedWarningEnabled && speedKmh >= overspeedThresholdKmh
        guard shouldWarn != isOverspeedWarningActive else { return }
        isOverspeedWarningActive = shouldWarn
        if shouldWarn && triggerHaptic {
            let feedback = UINotificationFeedbackGenerator()
            feedback.prepare()
            feedback.notificationOccurred(.warning)
        }
    }

    private func beginSession() {
        guard !isSessionActive else { return }
        if pendingAccelerationArm {
            pendingAccelerationArm = false
            accelerationState = .waitingForMovement
            canBeginAccelerationRun = speedKmh < accelerationStartThresholdKmh
        }
        if !hasUnfinishedSession {
            hasUnfinishedSession = true
            driveStartedAt = Date()
            lastValidLocation = nil
            routeCoordinates.removeAll(keepingCapacity: true)
        }
        isSessionActive = true
        sessionStartedAt = Date()
        previousLocation = nil
        locationManager.startUpdatingLocation()
    }

    private func recordRoutePoint(_ location: CLLocation, force: Bool = false) {
        guard CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy <= 50 else { return }

        if let lastPoint = routeCoordinates.last {
            let previous = CLLocation(latitude: lastPoint.latitude, longitude: lastPoint.longitude)
            let distance = location.distance(from: previous)
            let timeSinceLastPoint = location.timestamp.timeIntervalSince(lastPoint.timestamp)
            if distance < 2 || (!force && distance < 8 && timeSinceLastPoint < 8) { return }
        }

        routeCoordinates.append(DriveRoutePoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp
        ))
    }

    private func restoreAccelerationSettings() {
        if let data = defaults.data(forKey: accelerationAttemptsStorageKey),
           let storedAttempts = try? JSONDecoder().decode([AccelerationAttempt].self, from: data) {
            accelerationAttempts = storedAttempts.sorted { $0.date > $1.date }
        }

        let presetKey = "speedometer.acceleration.preset"
        let customTargetKey = "speedometer.acceleration.customTarget"
        let savedPreset = defaults.object(forKey: presetKey) as? Int ?? 50
        accelerationPreset = [20, 50, 100, -1].contains(savedPreset) ? savedPreset : 50
        customAccelerationTargetKmh = min(max(defaults.object(forKey: customTargetKey) as? Int ?? 80, 20), 240)
        accelerationTargetKmh = accelerationPreset == -1
            ? Double(customAccelerationTargetKmh)
            : Double(accelerationPreset)
        loadBestAccelerationTime()
    }

    private func loadBestAccelerationTime() {
        let targetKmh = Int(accelerationTargetKmh.rounded())
        let recordedBest = accelerationAttempts
            .filter { $0.targetKmh == targetKmh }
            .map(\.duration)
            .min()
        let key = "speedometer.acceleration.best.\(targetKmh)"
        bestAccelerationTime = recordedBest ?? defaults.object(forKey: key) as? Double
    }

    private func persistAccelerationAttempts() {
        guard let data = try? JSONEncoder().encode(accelerationAttempts) else { return }
        defaults.set(data, forKey: accelerationAttemptsStorageKey)
    }

    private func updateAccelerationTest(speedKmh: Double, at timestamp: Date) {
        switch accelerationState {
        case .waitingForMovement:
            if speedKmh < accelerationStartThresholdKmh {
                canBeginAccelerationRun = true
            } else if canBeginAccelerationRun {
                canBeginAccelerationRun = false
                accelerationRunStartedAt = timestamp
                accelerationState = .timing
            }
        case .timing:
            guard speedKmh >= accelerationTargetKmh else { return }
            let result = max(0, timestamp.timeIntervalSince(accelerationRunStartedAt ?? timestamp))
            let targetKmh = Int(accelerationTargetKmh.rounded())
            let previousBest = bestAccelerationTime
            accelerationResult = result
            accelerationState = .completed
            accelerationAttempts.insert(AccelerationAttempt(targetKmh: targetKmh, duration: result, date: timestamp), at: 0)
            persistAccelerationAttempts()

            if previousBest == nil || result < previousBest! {
                bestAccelerationTime = result
                isNewAccelerationBest = true
            }
            if let bestAccelerationTime {
                defaults.set(bestAccelerationTime, forKey: "speedometer.acceleration.best.\(targetKmh)")
            }
        case .ready, .completed:
            break
        }
    }
}
