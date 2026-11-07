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
    @Published private(set) var lastValidGPSFixAt: Date?
    @Published private(set) var locationUpdateFailed = false
    @Published private(set) var accelerationInterruptedForGPS = false
    @Published private(set) var isSessionActive = false
    @Published private(set) var isOverspeedWarningActive = false
    @Published private(set) var hasUnfinishedSession = false
    @Published var showDriveRecoveryChoice = false
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
    private let gpsFixStaleAfter: TimeInterval = 5
    private var gpsFreshnessTimer: Timer?
    private var previousLocation: CLLocation?
    private var lastValidLocation: CLLocation?
    @Published private(set) var routeCoordinates: [DriveRoutePoint] = []
    private var sessionStartedAt: Date?
    private var driveStartedAt: Date?
    private var driveID: UUID?
    private var lastProcessedLocationTimestamp: Date?
    private var routeSegmentIndex = 0
    private var interruptionGaps: [DriveInterruptionGap] = []
    private var pendingGapStartAt: Date?
    private var isAwaitingDriveRecoveryDecision = false
    private var accelerationRunStartedAt: Date?
    @Published private(set) var canBeginAccelerationRun = false
    private var pendingAccelerationArm = false
    private var pendingSessionStart = false
    private let accelerationStartThresholdKmh = 2.0
    private var overspeedWarningEnabled = false
    private var overspeedThresholdKmh = 100.0
    private var lastSnapshotWriteAt = Date.distantPast
    private var lifecycleObservers: [NSObjectProtocol] = []

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 2
        locationManager.activityType = .automotiveNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        restoreAccelerationSettings()
        restoreActiveDriveSnapshot()
        observeAppLifecycle()
    }

    var isGPSFixStale: Bool {
        guard isSessionActive, let lastValidGPSFixAt, !locationUpdateFailed else { return false }
        return Date().timeIntervalSince(lastValidGPSFixAt) > gpsFixStaleAfter
    }

    private var hasCurrentGPSFix: Bool {
        guard isSessionActive, hasGPSFix, let lastValidGPSFixAt else { return false }
        return Date().timeIntervalSince(lastValidGPSFixAt) <= gpsFixStaleAfter
    }

    var gpsStatusTitle: String {
        if hasCurrentGPSFix { return "GPS LOCKED" }
        switch authorizationStatus {
        case .denied, .restricted:
            return "LOCATION OFF"
        case .notDetermined:
            return "GPS STANDBY"
        case .authorizedAlways, .authorizedWhenInUse:
            if locationUpdateFailed { return "GPS UNAVAILABLE" }
            if isGPSFixStale { return "GPS STALE" }
            return isSessionActive ? "SEARCHING FOR GPS" : "GPS READY"
        @unknown default:
            return "GPS STANDBY"
        }
    }

    var gpsStatusDetail: String {
        if hasCurrentGPSFix { return "Accuracy ±\(Int(horizontalAccuracy.rounded())) m" }
        switch authorizationStatus {
        case .denied, .restricted:
            return "Allow location access in Settings"
        case .notDetermined:
            return "Start a session to connect GPS"
        case .authorizedAlways, .authorizedWhenInUse:
            if locationUpdateFailed { return "Location updates failed · retrying" }
            if isGPSFixStale { return "Last GPS fix is stale · searching" }
            return isSessionActive ? "Searching for a fresh GPS fix" : "Ready when you are"
        @unknown default:
            return "Waiting for location permission"
        }
    }

    func elapsedTime(at date: Date = .now) -> TimeInterval {
        elapsedSeconds + (sessionStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    func refreshLiveActivity() {
        updateDriveLiveActivity()
    }

    private func liveActivityState(at date: Date = .now, ended: Bool = false) -> VeluraDriveActivityAttributes.ContentState {
        let gpsFreshness: VeluraDriveActivityAttributes.ContentState.GPSFreshness
        if authorizationStatus == .denied || authorizationStatus == .restricted || locationUpdateFailed {
            gpsFreshness = .unavailable
        } else if hasCurrentGPSFix {
            gpsFreshness = .good
        } else if lastValidGPSFixAt != nil {
            gpsFreshness = .stale
        } else if hasUnfinishedSession && !isSessionActive {
            gpsFreshness = .unavailable
        } else {
            gpsFreshness = .searching
        }

        return VeluraDriveActivityAttributes.ContentState(
            speedKmh: speedKmh,
            elapsedSeconds: elapsedTime(at: date),
            distanceKm: distanceKm,
            topSpeedKmh: topSpeedKmh,
            gpsFreshness: gpsFreshness,
            updatedAt: date,
            isRunning: isSessionActive && !ended,
            isEnded: ended,
            usesMiles: defaults.bool(forKey: "speedometer.usesMiles")
        )
    }

    private func updateDriveLiveActivity(at date: Date = .now) {
        guard hasUnfinishedSession, let driveID, let driveStartedAt else { return }
        let state = liveActivityState(at: date)
        DriveLiveActivityController.shared.startOrUpdate(driveID: driveID, startedAt: driveStartedAt, state: state)
    }

    private func endDriveLiveActivity(at date: Date) {
        guard let driveID, hasUnfinishedSession else { return }
        DriveLiveActivityController.shared.end(driveID: driveID, state: liveActivityState(at: date, ended: true))
    }

    var driveRecoveryMessage: String {
        let checkpoint = (pendingGapStartAt ?? driveStartedAt ?? .now)
            .formatted(date: .abbreviated, time: .shortened)
        return "Velura found an unfinished drive. Last saved checkpoint: \(checkpoint). No new location data has been recorded since. Resume to continue in a separate route segment, or end the drive to save only its recorded portion; missing time, speed, distance, and route points will not be estimated."
    }

    var accelerationStatusTitle: String {
        switch accelerationState {
        case .ready:
            if accelerationInterruptedForGPS { return "GPS INTERRUPTED" }
            if isSessionActive && !hasCurrentGPSFix { return gpsStatusTitle }
            if authorizationStatus == .denied || authorizationStatus == .restricted { return gpsStatusTitle }
            return "READY"
        case .waitingForMovement:
            if !isSessionActive || !hasCurrentGPSFix { return gpsStatusTitle }
            return canBeginAccelerationRun ? "ARMED" : "WAIT FOR STOP"
        case .timing:
            return "TIMING"
        case .completed:
            return isNewAccelerationBest ? "NEW BEST" : "COMPLETE"
        }
    }

    func accelerationStatusDetail(target: Int, unit: String) -> String {
        switch accelerationState {
        case .ready:
            if accelerationInterruptedForGPS {
                return "GPS was lost; wait for a fresh fix and arm again"
            }
            if (isSessionActive && !hasCurrentGPSFix) || authorizationStatus == .denied || authorizationStatus == .restricted {
                return gpsStatusDetail
            }
            return "Start from a standstill to begin timing"
        case .waitingForMovement:
            if !isSessionActive || !hasCurrentGPSFix {
                return gpsStatusDetail == "Allow location access in Settings"
                    ? "Allow location access to measure your launch"
                    : gpsStatusDetail
            }
            return canBeginAccelerationRun
                ? "Accelerate to \(target) \(unit) to start timing"
                : "Come to a full stop to arm the timer"
        case .timing:
            return "Accelerate to \(target) \(unit)"
        case .completed:
            return isNewAccelerationBest ? "Target reached · new best saved" : "Target reached · run saved"
        }
    }

    var accelerationPrimaryActionTitle: String {
        switch accelerationState {
        case .ready: "Arm test"
        case .waitingForMovement: "Waiting for launch"
        case .timing: "Timing run"
        case .completed: "Try again"
        }
    }

    var accelerationPrimaryActionSymbol: String {
        switch accelerationState {
        case .ready: "play.fill"
        case .waitingForMovement: "hourglass"
        case .timing: "speedometer"
        case .completed: "arrow.counterclockwise"
        }
    }

    var isAccelerationPrimaryActionEnabled: Bool {
        accelerationState != .waitingForMovement && accelerationState != .timing
    }

    func configureOverspeedWarning(enabled: Bool, thresholdKmh: Double) {
        overspeedWarningEnabled = enabled
        overspeedThresholdKmh = max(1, thresholdKmh)
        updateOverspeedWarning(triggerHaptic: false)
    }

    func requestLocationAuthorization() {
        guard locationManager.authorizationStatus == .notDetermined else {
            authorizationStatus = locationManager.authorizationStatus
            return
        }
        locationManager.requestWhenInUseAuthorization()
    }

    func refreshLocationAuthorizationStatus() {
        authorizationStatus = locationManager.authorizationStatus
    }

    func startSession() {
        guard !isAwaitingDriveRecoveryDecision else {
            showDriveRecoveryChoice = true
            return
        }

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

    func resumeRecoveredDrive() {
        guard hasUnfinishedSession else {
            showDriveRecoveryChoice = false
            return
        }
        isAwaitingDriveRecoveryDecision = false
        showDriveRecoveryChoice = false
        startSession()
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
        guard !isAwaitingDriveRecoveryDecision else {
            showDriveRecoveryChoice = true
            return
        }
        guard accelerationState != .waitingForMovement && accelerationState != .timing else { return }
        accelerationResult = nil
        isNewAccelerationBest = false
        accelerationInterruptedForGPS = false
        accelerationRunStartedAt = nil
        accelerationState = .waitingForMovement
        canBeginAccelerationRun = hasCurrentGPSFix && speedKmh < accelerationStartThresholdKmh

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
        accelerationInterruptedForGPS = false
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
        pendingGapStartAt = pendingGapStartAt ?? lastProcessedLocationTimestamp ?? Date()
        isSessionActive = false
        stopGPSFreshnessMonitoring()
        hasGPSFix = false
        lastValidGPSFixAt = nil
        locationUpdateFailed = false
        speedKmh = 0
        updateOverspeedWarning(triggerHaptic: false)
        previousLocation = nil
        updateDriveLiveActivity()
        if accelerationState == .waitingForMovement || accelerationState == .timing {
            resetAccelerationTest()
        }
        accelerationInterruptedForGPS = false
        configureBackgroundLocationUpdates(active: false)
        locationManager.stopUpdatingLocation()
        persistActiveDrive(force: true)
    }

    func finishSession() {
        guard hasUnfinishedSession else { return }
        if isSessionActive {
            configureBackgroundLocationUpdates(active: false)
            locationManager.stopUpdatingLocation()
        }

        let finishedAt = Date()
        if let lastValidLocation {
            recordRoutePoint(lastValidLocation, force: true)
        }
        completePendingGap(at: finishedAt)
        let duration = elapsedTime(at: finishedAt)
        if duration > 0 {
            DriveHistoryStore.shared.add(DriveRecord(
                id: driveID ?? UUID(),
                date: driveStartedAt ?? finishedAt,
                duration: duration,
                distanceKm: distanceKm,
                topSpeedKmh: topSpeedKmh,
                routeCoordinates: routeCoordinates.count >= 2 ? routeCoordinates : [],
                interruptionGaps: interruptionGaps
            ))
        }
        endDriveLiveActivity(at: finishedAt)
        resetSession()
    }

    func resetSession() {
        if hasUnfinishedSession {
            endDriveLiveActivity(at: .now)
        }
        if isSessionActive {
            configureBackgroundLocationUpdates(active: false)
            locationManager.stopUpdatingLocation()
        }
        pendingSessionStart = false
        isSessionActive = false
        stopGPSFreshnessMonitoring()
        hasUnfinishedSession = false
        isAwaitingDriveRecoveryDecision = false
        showDriveRecoveryChoice = false
        driveID = nil
        lastProcessedLocationTimestamp = nil
        routeSegmentIndex = 0
        interruptionGaps.removeAll()
        pendingGapStartAt = nil
        ActiveDriveStore.shared.clear()
        lastSnapshotWriteAt = .distantPast
        if accelerationState == .waitingForMovement || accelerationState == .timing {
            resetAccelerationTest()
        }
        accelerationInterruptedForGPS = false
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
        lastValidGPSFixAt = nil
        locationUpdateFailed = false
        updateOverspeedWarning(triggerHaptic: false)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .denied || authorizationStatus == .restricted {
            hasGPSFix = false
            lastValidGPSFixAt = nil
            locationUpdateFailed = false
            speedKmh = 0
            previousLocation = nil
            interruptAccelerationTestForGPSIssue()

            if isSessionActive {
                let interruptionAt = Date()
                if let sessionStartedAt {
                    elapsedSeconds += max(0, interruptionAt.timeIntervalSince(sessionStartedAt))
                }
                sessionStartedAt = nil
                isSessionActive = false
                stopGPSFreshnessMonitoring()
                pendingGapStartAt = pendingGapStartAt ?? lastProcessedLocationTimestamp ?? interruptionAt
                configureBackgroundLocationUpdates(active: false)
                locationManager.stopUpdatingLocation()
                isAwaitingDriveRecoveryDecision = hasUnfinishedSession
                persistActiveDrive(force: true)
                updateDriveLiveActivity(at: interruptionAt)
                if hasUnfinishedSession {
                    showLocationAlert = true
                }
            }
            updateOverspeedWarning(triggerHaptic: false)
        }
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
        let receivedAt = Date()
        var receivedValidLocation = false

        for location in locations where location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 50 {
            let fixAge = receivedAt.timeIntervalSince(location.timestamp)
            guard fixAge >= -1 && fixAge <= gpsFixStaleAfter else { continue }
            guard lastProcessedLocationTimestamp.map({ location.timestamp > $0 }) ?? true else { continue }

            if pendingGapStartAt == nil,
               let previousLocation,
               location.timestamp.timeIntervalSince(previousLocation.timestamp) > gpsFixStaleAfter {
                pendingGapStartAt = lastProcessedLocationTimestamp ?? previousLocation.timestamp
            }
            if pendingGapStartAt != nil {
                completePendingGap(at: location.timestamp)
            }
            lastProcessedLocationTimestamp = location.timestamp
            receivedValidLocation = true

            horizontalAccuracy = location.horizontalAccuracy
            hasGPSFix = true
            lastValidGPSFixAt = receivedAt
            locationUpdateFailed = false
            lastValidLocation = location
            recordRoutePoint(location)

            if location.speed >= 0 {
                let measuredSpeed = max(0, location.speed * 3.6)
                speedKmh = measuredSpeed < 1.0 ? 0 : measuredSpeed
                topSpeedKmh = max(topSpeedKmh, speedKmh)
                updateAccelerationTest(speedKmh: speedKmh, at: location.timestamp)
                updateOverspeedWarning(triggerHaptic: true)
            } else {
                speedKmh = 0
                updateOverspeedWarning(triggerHaptic: false)
            }

            if let previousLocation {
                let distance = location.distance(from: previousLocation)
                let timeDelta = location.timestamp.timeIntervalSince(previousLocation.timestamp)
                if distance < 150 && timeDelta > 0 && timeDelta <= gpsFixStaleAfter {
                    distanceKm += distance / 1_000
                }
            }
            previousLocation = location
        }

        if receivedValidLocation {
            persistActiveDrive(force: true)
            updateDriveLiveActivity(at: receivedAt)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        authorizationStatus = manager.authorizationStatus
        hasGPSFix = false
        speedKmh = 0
        previousLocation = nil
        locationUpdateFailed = authorizationStatus != .denied && authorizationStatus != .restricted
        interruptAccelerationTestForGPSIssue()
        if isSessionActive {
            pendingGapStartAt = pendingGapStartAt ?? lastProcessedLocationTimestamp ?? Date()
            persistActiveDrive(force: true)
        }
        updateDriveLiveActivity()
        updateOverspeedWarning(triggerHaptic: false)
    }

    private func updateOverspeedWarning(triggerHaptic: Bool) {
        let shouldWarn = isSessionActive && hasCurrentGPSFix && overspeedWarningEnabled && speedKmh >= overspeedThresholdKmh
        guard shouldWarn != isOverspeedWarningActive else { return }
        isOverspeedWarningActive = shouldWarn
        if shouldWarn && triggerHaptic {
            let feedback = UINotificationFeedbackGenerator()
            feedback.prepare()
            feedback.notificationOccurred(.warning)
        }
    }

    private func startGPSFreshnessMonitoring() {
        stopGPSFreshnessMonitoring()
        gpsFreshnessTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshGPSFreshness()
            }
        }
    }

    private func stopGPSFreshnessMonitoring() {
        gpsFreshnessTimer?.invalidate()
        gpsFreshnessTimer = nil
    }

    private func refreshGPSFreshness() {
        guard isSessionActive,
              let lastValidGPSFixAt,
              Date().timeIntervalSince(lastValidGPSFixAt) > gpsFixStaleAfter,
              hasGPSFix else { return }

        hasGPSFix = false
        speedKmh = 0
        pendingGapStartAt = pendingGapStartAt ?? lastProcessedLocationTimestamp ?? Date()
        previousLocation = nil
        interruptAccelerationTestForGPSIssue()
        persistActiveDrive(force: true)
        updateDriveLiveActivity()
        updateOverspeedWarning(triggerHaptic: false)
    }

    private func interruptAccelerationTestForGPSIssue() {
        guard accelerationState == .waitingForMovement || accelerationState == .timing else { return }
        pendingAccelerationArm = false
        canBeginAccelerationRun = false
        accelerationRunStartedAt = nil
        accelerationResult = nil
        isNewAccelerationBest = false
        accelerationState = .ready
        accelerationInterruptedForGPS = true
    }

    private func beginSession() {
        guard !isSessionActive else { return }
        let sessionResumedAt = Date()
        hasGPSFix = false
        lastValidGPSFixAt = nil
        locationUpdateFailed = false
        horizontalAccuracy = -1
        speedKmh = 0
        if pendingAccelerationArm {
            pendingAccelerationArm = false
            accelerationState = .waitingForMovement
            canBeginAccelerationRun = false
        }
        if !hasUnfinishedSession {
            hasUnfinishedSession = true
            driveStartedAt = sessionResumedAt
            driveID = UUID()
            lastProcessedLocationTimestamp = nil
            routeSegmentIndex = 0
            interruptionGaps.removeAll()
            pendingGapStartAt = nil
            lastValidLocation = nil
            routeCoordinates.removeAll(keepingCapacity: true)
        }
        isAwaitingDriveRecoveryDecision = false
        isSessionActive = true
        sessionStartedAt = sessionResumedAt
        previousLocation = nil
        startGPSFreshnessMonitoring()
        configureBackgroundLocationUpdates(active: true)
        locationManager.startUpdatingLocation()
        persistActiveDrive(force: true)
        updateDriveLiveActivity(at: sessionResumedAt)
    }

    private func completePendingGap(at end: Date) {
        guard let start = pendingGapStartAt else { return }
        pendingGapStartAt = nil
        previousLocation = nil
        guard end > start else { return }
        interruptionGaps.append(DriveInterruptionGap(startAt: start, endAt: end))
        routeSegmentIndex += 1
    }

    private func recordRoutePoint(_ location: CLLocation, force: Bool = false) {
        guard CLLocationCoordinate2DIsValid(location.coordinate), location.horizontalAccuracy <= 50 else { return }

        if let lastPoint = routeCoordinates.last, lastPoint.segmentIndex == routeSegmentIndex {
            let previous = CLLocation(latitude: lastPoint.latitude, longitude: lastPoint.longitude)
            let distance = location.distance(from: previous)
            let timeSinceLastPoint = location.timestamp.timeIntervalSince(lastPoint.timestamp)
            if distance < 2 || (!force && distance < 8 && timeSinceLastPoint < 8) { return }
        }

        routeCoordinates.append(DriveRoutePoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            timestamp: location.timestamp,
            segmentIndex: routeSegmentIndex
        ))
    }

    private var supportsBackgroundLocation: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String])?.contains("location") == true
    }

    private func configureBackgroundLocationUpdates(active: Bool) {
        guard supportsBackgroundLocation else { return }
        locationManager.allowsBackgroundLocationUpdates = active
        locationManager.showsBackgroundLocationIndicator = active
    }

    private func observeAppLifecycle() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification,
            UIApplication.willTerminateNotification
        ]
        for name in names {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.persistActiveDrive(force: true)
                }
            }
            lifecycleObservers.append(observer)
        }

        let activeObserver = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshGPSFreshness()
                self?.persistActiveDrive(force: true)
            }
        }
        lifecycleObservers.append(activeObserver)
    }

    private func persistActiveDrive(force: Bool) {
        guard hasUnfinishedSession, let driveStartedAt else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastSnapshotWriteAt) >= 2 else { return }
        lastSnapshotWriteAt = now
        ActiveDriveStore.shared.save(ActiveDriveSnapshot(
            sessionID: driveID,
            startedAt: driveStartedAt,
            elapsedSeconds: elapsedTime(at: now),
            distanceKm: distanceKm,
            topSpeedKmh: topSpeedKmh,
            routeCoordinates: routeCoordinates,
            updatedAt: now,
            lastLocationAt: lastProcessedLocationTimestamp,
            routeSegmentIndex: routeSegmentIndex,
            interruptionGaps: interruptionGaps,
            pendingGapStartAt: pendingGapStartAt
        ))
    }

    private func restoreActiveDriveSnapshot() {
        guard let snapshot = ActiveDriveStore.shared.load() else { return }
        let alreadyCompleted: Bool
        if let sessionID = snapshot.sessionID {
            alreadyCompleted = DriveHistoryStore.shared.drives.contains { $0.id == sessionID }
        } else {
            alreadyCompleted = DriveHistoryStore.shared.drives.contains {
                abs($0.date.timeIntervalSince(snapshot.startedAt)) < 1
            }
        }
        guard !alreadyCompleted else {
            ActiveDriveStore.shared.clear()
            return
        }

        hasUnfinishedSession = true
        driveID = snapshot.sessionID ?? UUID()
        driveStartedAt = snapshot.startedAt
        elapsedSeconds = snapshot.elapsedSeconds
        distanceKm = snapshot.distanceKm
        topSpeedKmh = snapshot.topSpeedKmh
        routeCoordinates = snapshot.routeCoordinates
        lastProcessedLocationTimestamp = snapshot.lastLocationAt ?? snapshot.routeCoordinates.last?.timestamp
        routeSegmentIndex = max(snapshot.routeSegmentIndex, snapshot.routeCoordinates.map(\.segmentIndex).max() ?? 0)
        interruptionGaps = snapshot.interruptionGaps
        pendingGapStartAt = snapshot.pendingGapStartAt
            ?? lastProcessedLocationTimestamp
            ?? snapshot.updatedAt
        previousLocation = nil
        lastValidLocation = nil
        lastSnapshotWriteAt = snapshot.updatedAt
        isAwaitingDriveRecoveryDecision = true
        showDriveRecoveryChoice = true
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
        guard hasCurrentGPSFix else { return }
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
