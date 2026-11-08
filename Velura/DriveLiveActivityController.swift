import ActivityKit
import Foundation
import OSLog
import UIKit

public struct VeluraDriveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public enum GPSFreshness: String, Codable, Hashable {
            case good
            case searching
            case stale
            case unreliable
            case unavailable
        }

        public var speedKmh: Double
        public var elapsedSeconds: TimeInterval
        public var distanceKm: Double
        public var topSpeedKmh: Double
        public var gpsFreshness: GPSFreshness
        public var updatedAt: Date
        public var isRunning: Bool
        public var isEnded: Bool
        public var usesMiles: Bool
        public var themeRawValue: String
        public var appearanceModeRawValue: String
        public var dialStyleRawValue: String
        public var displayScaleRawValue: String
        public var dialMaximum: Double

        public init(
            speedKmh: Double,
            elapsedSeconds: TimeInterval,
            distanceKm: Double,
            topSpeedKmh: Double,
            gpsFreshness: GPSFreshness,
            updatedAt: Date,
            isRunning: Bool,
            isEnded: Bool,
            usesMiles: Bool,
            themeRawValue: String = "midnight",
            appearanceModeRawValue: String = "palette",
            dialStyleRawValue: String = "classic",
            displayScaleRawValue: String = "standard",
            dialMaximum: Double = 50
        ) {
            self.speedKmh = speedKmh
            self.elapsedSeconds = elapsedSeconds
            self.distanceKm = distanceKm
            self.topSpeedKmh = topSpeedKmh
            self.gpsFreshness = gpsFreshness
            self.updatedAt = updatedAt
            self.isRunning = isRunning
            self.isEnded = isEnded
            self.usesMiles = usesMiles
            self.themeRawValue = themeRawValue
            self.appearanceModeRawValue = appearanceModeRawValue
            self.dialStyleRawValue = dialStyleRawValue
            self.displayScaleRawValue = displayScaleRawValue
            self.dialMaximum = dialMaximum
        }

        private enum CodingKeys: String, CodingKey {
            case speedKmh, elapsedSeconds, distanceKm, topSpeedKmh, gpsFreshness
            case updatedAt, isRunning, isEnded, usesMiles
            case themeRawValue, appearanceModeRawValue, dialStyleRawValue, displayScaleRawValue, dialMaximum
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            speedKmh = try container.decode(Double.self, forKey: .speedKmh)
            elapsedSeconds = try container.decode(TimeInterval.self, forKey: .elapsedSeconds)
            distanceKm = try container.decode(Double.self, forKey: .distanceKm)
            topSpeedKmh = try container.decode(Double.self, forKey: .topSpeedKmh)
            gpsFreshness = try container.decode(GPSFreshness.self, forKey: .gpsFreshness)
            updatedAt = try container.decode(Date.self, forKey: .updatedAt)
            isRunning = try container.decode(Bool.self, forKey: .isRunning)
            isEnded = try container.decode(Bool.self, forKey: .isEnded)
            usesMiles = try container.decode(Bool.self, forKey: .usesMiles)
            themeRawValue = try container.decodeIfPresent(String.self, forKey: .themeRawValue) ?? "midnight"
            appearanceModeRawValue = try container.decodeIfPresent(String.self, forKey: .appearanceModeRawValue) ?? "palette"
            dialStyleRawValue = try container.decodeIfPresent(String.self, forKey: .dialStyleRawValue) ?? "classic"
            displayScaleRawValue = try container.decodeIfPresent(String.self, forKey: .displayScaleRawValue) ?? "standard"
            dialMaximum = try container.decodeIfPresent(Double.self, forKey: .dialMaximum) ?? 50
        }
    }

    public var driveID: UUID
    public var startedAt: Date
}

@MainActor
final class DriveLiveActivityController {
    static let shared = DriveLiveActivityController()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.velura.app", category: "LiveActivity")
    private let minimumUpdateInterval: TimeInterval = 4
    private let activeContentStaleAfter: TimeInterval = 15
    private var activity: Activity<VeluraDriveActivityAttributes>?
    private var currentDriveID: UUID?
    private var requestAttempted = false
    private var requestInFlightDriveIDs: Set<UUID> = []
    private var pendingEndingStates: [UUID: VeluraDriveActivityAttributes.ContentState] = [:]
    private var isDismissedForCurrentDrive = false
    private var lastSubmittedAt = Date.distantPast
    private var pendingState: VeluraDriveActivityAttributes.ContentState?
    private var updateTask: Task<Void, Never>?
    private var activityStateTask: Task<Void, Never>?

    private init() { }

    func reconcile(
        activeDriveID: UUID?,
        state: VeluraDriveActivityAttributes.ContentState?,
        completedDrives: [DriveRecord]
    ) {
        updateTask?.cancel()
        updateTask = nil
        activityStateTask?.cancel()
        activityStateTask = nil
        activity = nil
        currentDriveID = activeDriveID
        requestAttempted = false
        isDismissedForCurrentDrive = false
        pendingState = nil
        lastSubmittedAt = .distantPast

        let completedDrivesByID = Dictionary(uniqueKeysWithValues: completedDrives.map { ($0.id, $0) })
        let existingActivities = Activity<VeluraDriveActivityAttributes>.activities
        let liveActivities = existingActivities.filter { $0.activityState == .active || $0.activityState == .stale }
        let matchingActivities = activeDriveID.map { driveID in
            liveActivities.filter { $0.attributes.driveID == driveID }
        } ?? []
        let matchingActivity = matchingActivities.first

        for existingActivity in liveActivities {
            if existingActivity.id == matchingActivity?.id { continue }

            if let activeDriveID, existingActivity.attributes.driveID == activeDriveID {
                endImmediately(existingActivity)
            } else if let completedDrive = completedDrivesByID[existingActivity.attributes.driveID] {
                end(existingActivity, with: completedState(from: existingActivity.content.state, drive: completedDrive))
            } else {
                endImmediately(existingActivity)
            }
        }

        guard let activeDriveID else { return }
        if let matchingActivity {
            activity = matchingActivity
            observeActivityState(of: matchingActivity, driveID: activeDriveID)
            if let state {
                scheduleUpdate(state, immediately: true)
            }
        } else {
            isDismissedForCurrentDrive = existingActivities.contains {
                $0.attributes.driveID == activeDriveID && $0.activityState == .dismissed
            }
        }
    }

    func startOrUpdate(
        driveID: UUID,
        startedAt: Date,
        state: VeluraDriveActivityAttributes.ContentState,
        allowRequest: Bool = true
    ) {
        if currentDriveID != driveID {
            guard UIApplication.shared.applicationState == .active else { return }
            updateTask?.cancel()
            activityStateTask?.cancel()
            activity = nil
            pendingState = nil
            currentDriveID = driveID
            requestAttempted = false
            isDismissedForCurrentDrive = false
        }

        guard currentDriveID == driveID, !isDismissedForCurrentDrive else { return }

        if let activity, activity.attributes.driveID == driveID {
            scheduleUpdate(state, immediately: false)
            return
        }

        if let existingActivity = Activity<VeluraDriveActivityAttributes>.activities.first(where: {
            $0.attributes.driveID == driveID && ($0.activityState == .active || $0.activityState == .stale)
        }) {
            activity = existingActivity
            observeActivityState(of: existingActivity, driveID: driveID)
            scheduleUpdate(state, immediately: true)
            return
        }

        if requestInFlightDriveIDs.contains(driveID) {
            pendingState = state
            return
        }

        guard allowRequest,
              !requestAttempted,
              ActivityAuthorizationInfo().areActivitiesEnabled,
              UIApplication.shared.applicationState == .active else { return }

        requestAttempted = true
        requestInFlightDriveIDs.insert(driveID)
        let attributes = VeluraDriveActivityAttributes(driveID: driveID, startedAt: startedAt)
        let initialContent = activityContent(for: state)

        Task { [weak self] in
            do {
                let requestedActivity = try Activity.request(
                    attributes: attributes,
                    content: initialContent,
                    pushType: nil
                )
                guard let self else {
                    await requestedActivity.end(nil, dismissalPolicy: .immediate)
                    return
                }
                self.requestInFlightDriveIDs.remove(driveID)

                guard self.currentDriveID == driveID, !self.isDismissedForCurrentDrive else {
                    if let finalState = self.pendingEndingStates.removeValue(forKey: driveID) {
                        await requestedActivity.end(
                            ActivityContent(state: finalState, staleDate: nil),
                            dismissalPolicy: .after(Date().addingTimeInterval(30 * 60))
                        )
                    } else {
                        await requestedActivity.end(nil, dismissalPolicy: .immediate)
                    }
                    return
                }

                self.activity = requestedActivity
                self.lastSubmittedAt = Date()
                self.observeActivityState(of: requestedActivity, driveID: driveID)
                if let latestState = self.pendingState {
                    self.pendingState = nil
                    self.scheduleUpdate(latestState, immediately: true)
                }
            } catch {
                self?.requestInFlightDriveIDs.remove(driveID)
                self?.logger.error("Could not start the drive Live Activity: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func update(driveID: UUID, state: VeluraDriveActivityAttributes.ContentState) {
        guard currentDriveID == driveID, !isDismissedForCurrentDrive else { return }
        scheduleUpdate(state, immediately: false)
    }

    func end(driveID: UUID, state: VeluraDriveActivityAttributes.ContentState) {
        let isCurrentDrive = currentDriveID == driveID
        if isCurrentDrive {
            updateTask?.cancel()
            updateTask = nil
            pendingState = nil
            currentDriveID = nil
            requestAttempted = false
            isDismissedForCurrentDrive = false
        }

        let matchingActivity = activity.flatMap { $0.attributes.driveID == driveID ? $0 : nil }
            ?? Activity<VeluraDriveActivityAttributes>.activities.first {
                $0.attributes.driveID == driveID && ($0.activityState == .active || $0.activityState == .stale)
            }

        guard let matchingActivity else {
            if requestInFlightDriveIDs.contains(driveID) {
                pendingEndingStates[driveID] = state
            } else {
                pendingEndingStates.removeValue(forKey: driveID)
            }
            if isCurrentDrive {
                activity = nil
                activityStateTask?.cancel()
                activityStateTask = nil
            }
            return
        }

        if isCurrentDrive {
            activity = nil
            activityStateTask?.cancel()
            activityStateTask = nil
        }

        if requestInFlightDriveIDs.contains(driveID) {
            pendingEndingStates[driveID] = state
        }
        let finalContent = ActivityContent(state: state, staleDate: nil)
        Task { [weak self] in
            await matchingActivity.end(
                finalContent,
                dismissalPolicy: .after(Date().addingTimeInterval(30 * 60))
            )
            self?.pendingEndingStates.removeValue(forKey: driveID)
        }
    }

    private func activityContent(
        for state: VeluraDriveActivityAttributes.ContentState
    ) -> ActivityContent<VeluraDriveActivityAttributes.ContentState> {
        let staleDate = state.isEnded ? nil : Date().addingTimeInterval(activeContentStaleAfter)
        return ActivityContent(state: state, staleDate: staleDate)
    }

    private func endImmediately(_ activity: Activity<VeluraDriveActivityAttributes>) {
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func end(
        _ activity: Activity<VeluraDriveActivityAttributes>,
        with state: VeluraDriveActivityAttributes.ContentState
    ) {
        Task {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(30 * 60))
            )
        }
    }

    private func completedState(
        from currentState: VeluraDriveActivityAttributes.ContentState,
        drive: DriveRecord
    ) -> VeluraDriveActivityAttributes.ContentState {
        var state = currentState
        state.speedKmh = 0
        state.elapsedSeconds = drive.duration
        state.distanceKm = drive.distanceKm
        state.topSpeedKmh = drive.topSpeedKmh
        state.updatedAt = .now
        state.isRunning = false
        state.isEnded = true
        return state
    }

    private func scheduleUpdate(_ state: VeluraDriveActivityAttributes.ContentState, immediately: Bool) {
        pendingState = state
        guard activity != nil else { return }

        let remaining = minimumUpdateInterval - Date().timeIntervalSince(lastSubmittedAt)
        if immediately || remaining <= 0 {
            updateTask?.cancel()
            updateTask = nil
            submitPendingUpdate()
        } else if updateTask == nil {
            let delay = UInt64(remaining * 1_000_000_000)
            updateTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                self?.submitPendingUpdate()
            }
        }
    }

    private func submitPendingUpdate() {
        updateTask = nil
        guard let activity, let state = pendingState else { return }
        pendingState = nil
        lastSubmittedAt = Date()
        let content = activityContent(for: state)
        Task {
            await activity.update(content)
        }
    }

    private func observeActivityState(of activity: Activity<VeluraDriveActivityAttributes>, driveID: UUID) {
        activityStateTask?.cancel()
        activityStateTask = Task { [weak self] in
            for await state in activity.activityStateUpdates {
                guard !Task.isCancelled else { return }
                guard state == .dismissed || state == .ended else { continue }
                guard let self, self.currentDriveID == driveID else { return }
                self.isDismissedForCurrentDrive = true
                self.activity = nil
                self.pendingState = nil
                self.updateTask?.cancel()
                self.updateTask = nil
                return
            }
        }
    }
}
