import ActivityKit
import SwiftUI
import WidgetKit

public struct VeluraDriveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public enum GPSFreshness: String, Codable, Hashable {
            case good
            case searching
            case stale
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
    }

    public var driveID: UUID
    public var startedAt: Date
}

private enum LiveActivityPalette {
    static let background = Color(red: 0.025, green: 0.09, blue: 0.15)
    static let surface = Color(red: 0.035, green: 0.14, blue: 0.22)
    static let cyan = Color(red: 0.25, green: 0.82, blue: 0.94)
    static let mint = Color(red: 0.23, green: 0.82, blue: 0.60)
    static let secondary = Color(red: 0.68, green: 0.77, blue: 0.86)
    static let warning = Color(red: 1.0, green: 0.68, blue: 0.34)
}

private struct LockScreenDriveActivityView: View {
    let context: ActivityViewContext<VeluraDriveActivityAttributes>

    private var state: VeluraDriveActivityAttributes.ContentState { context.state }
    private var distanceUnit: String { state.usesMiles ? "mi" : "km" }
    private var speedUnit: String { state.usesMiles ? "mph" : "km/h" }
    private var speedConversion: Double { state.usesMiles ? 0.621371 : 1 }
    private var elapsedAnchor: Date {
        state.updatedAt.addingTimeInterval(-max(0, state.elapsedSeconds))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LiveActivityPalette.cyan)
                Text("VELURA · \(state.isEnded ? "DRIVE COMPLETE" : "DRIVE ACTIVE")")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(LiveActivityPalette.secondary)
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(LiveActivityPalette.secondary.opacity(0.9))
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int((state.speedKmh * speedConversion).rounded()))")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(speedUnit)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiveActivityPalette.secondary)
            }
            .foregroundStyle(.white)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Current speed, \(Int((state.speedKmh * speedConversion).rounded())) \(speedUnit)")

            Text(state.isEnded ? "FINAL SPEED" : "CURRENT SPEED")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(LiveActivityPalette.secondary)

            divider
            HStack(spacing: 0) {
                metric(title: "DISTANCE", value: String(format: "%.1f %@", state.distanceKm * (state.usesMiles ? 0.621371 : 1), distanceUnit))
                Rectangle()
                    .fill(LiveActivityPalette.secondary.opacity(0.34))
                    .frame(width: 1, height: 43)
                    .padding(.horizontal, 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text("DURATION")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(LiveActivityPalette.secondary)
                    if state.isRunning && !state.isEnded {
                        Text(timerInterval: elapsedAnchor...Date.distantFuture, countsDown: false, showsHours: true)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Text(formattedDuration(state.elapsedSeconds))
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2)

            divider
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Text("TOP SPEED")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(0.4)
                        .foregroundStyle(LiveActivityPalette.secondary)
                    Text("\(Int((state.topSpeedKmh * speedConversion).rounded())) \(speedUnit)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 4)
                Rectangle()
                    .fill(LiveActivityPalette.secondary.opacity(0.34))
                    .frame(width: 1, height: 18)
                gpsStatus
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LiveActivityPalette.surface.opacity(0.96))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
        }
        .activityBackgroundTint(LiveActivityPalette.background.opacity(0.9))
        .activitySystemActionForegroundColor(.white)
        .widgetURL(URL(string: "velura://drive/active"))
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Rectangle()
            .fill(LiveActivityPalette.secondary.opacity(0.28))
            .frame(height: 1)
    }

    private var gpsStatus: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(gpsColor)
                .frame(width: 8, height: 8)
            Text(gpsText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .tracking(0.35)
                .foregroundStyle(LiveActivityPalette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var gpsColor: Color {
        switch state.gpsFreshness {
        case .good: LiveActivityPalette.mint
        case .searching: LiveActivityPalette.cyan
        case .stale, .unavailable: LiveActivityPalette.warning
        }
    }

    private var gpsText: String {
        switch state.gpsFreshness {
        case .good:
            let age = Date().timeIntervalSince(state.updatedAt)
            return age < 60 ? "GPS GOOD · UPDATED NOW" : "GPS GOOD · RECENT"
        case .searching: return "GPS SEARCHING"
        case .stale: return "GPS STALE"
        case .unavailable: return "GPS UNAVAILABLE"
        }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(LiveActivityPalette.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DynamicIslandDriveActivityView {
    let context: ActivityViewContext<VeluraDriveActivityAttributes>

    private var state: VeluraDriveActivityAttributes.ContentState { context.state }
    private var speedUnit: String { state.usesMiles ? "mph" : "km/h" }
    private var distanceUnit: String { state.usesMiles ? "mi" : "km" }
    private var conversion: Double { state.usesMiles ? 0.621371 : 1 }
    private var elapsedAnchor: Date { state.updatedAt.addingTimeInterval(-max(0, state.elapsedSeconds)) }

    var body: DynamicIsland {
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                HStack(spacing: 7) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LiveActivityPalette.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VELURA")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(LiveActivityPalette.secondary)
                        Text(state.isEnded ? "DRIVE COMPLETE" : "DRIVE ACTIVE")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
            DynamicIslandExpandedRegion(.trailing) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(Int((state.speedKmh * conversion).rounded()))")
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text(speedUnit)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(LiveActivityPalette.secondary)
                }
            }
            DynamicIslandExpandedRegion(.bottom) {
                VStack(spacing: 10) {
                    Rectangle()
                        .fill(LiveActivityPalette.secondary.opacity(0.25))
                        .frame(height: 1)
                    HStack(spacing: 0) {
                        islandMetric("DISTANCE", value: String(format: "%.1f %@", state.distanceKm * conversion, distanceUnit))
                        islandDurationMetric
                        islandMetric("TOP SPEED", value: "\(Int((state.topSpeedKmh * conversion).rounded())) \(speedUnit)")
                    }
                    HStack(spacing: 6) {
                        Circle()
                            .fill(gpsColor)
                            .frame(width: 7, height: 7)
                        Text(gpsText)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(LiveActivityPalette.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 6)
            }
        } compactLeading: {
            Image(systemName: "speedometer")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LiveActivityPalette.cyan)
        } compactTrailing: {
            HStack(spacing: 2) {
                Text("\(Int((state.speedKmh * conversion).rounded()))")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(speedUnit)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(LiveActivityPalette.secondary)
            }
            .foregroundStyle(.white)
        } minimal: {
            Image(systemName: "speedometer")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LiveActivityPalette.cyan)
        }
        .keylineTint(LiveActivityPalette.cyan)
        .widgetURL(URL(string: "velura://drive/active"))
    }

    private var islandDurationMetric: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("DURATION")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(LiveActivityPalette.secondary)
            Group {
                if state.isRunning && !state.isEnded {
                    Text(timerInterval: elapsedAnchor...Date.distantFuture, countsDown: false, showsHours: true)
                } else {
                    Text(formattedDuration(state.elapsedSeconds))
                }
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gpsColor: Color {
        switch state.gpsFreshness {
        case .good: LiveActivityPalette.mint
        case .searching: LiveActivityPalette.cyan
        case .stale, .unavailable: LiveActivityPalette.warning
        }
    }

    private var gpsText: String {
        switch state.gpsFreshness {
        case .good: "GPS GOOD"
        case .searching: "SEARCHING FOR GPS"
        case .stale: "GPS STALE"
        case .unavailable: "GPS UNAVAILABLE"
        }
    }

    private func islandMetric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(LiveActivityPalette.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func formattedDuration(_ interval: TimeInterval) -> String {
    let totalSeconds = max(0, Int(interval))
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
        : String(format: "%d:%02d", minutes, seconds)
}

struct VeluraLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VeluraDriveActivityAttributes.self) { context in
            LockScreenDriveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIslandDriveActivityView(context: context).body
        }
    }
}

@main
struct VeluraLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        VeluraLiveActivityWidget()
    }
}
