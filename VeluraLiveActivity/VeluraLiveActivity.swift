import ActivityKit
import SwiftUI
import WidgetKit

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

/// Accent colours derived from the driver's theme. Text always uses the
/// system's semantic colours so it stays legible over the system-provided
/// Liquid Glass background of the Lock Screen presentation.
private struct DrivePalette {
    let accent: Color
    let mint: Color
    let warning: Color

    init(theme: String, mode: String) {
        if mode == "palette" {
            switch theme {
            case "ocean":
                accent = Color(red: 0.24, green: 0.86, blue: 0.75)
                mint = Color(red: 0.42, green: 0.88, blue: 0.66)
            case "graphite":
                accent = Color(red: 1.0, green: 0.72, blue: 0.33)
                mint = Color(red: 0.48, green: 0.85, blue: 0.60)
            case "forest":
                accent = Color(red: 0.35, green: 0.85, blue: 0.56)
                mint = Color(red: 0.68, green: 0.87, blue: 0.55)
            case "ember":
                accent = Color(red: 0.95, green: 0.58, blue: 0.34)
                mint = Color(red: 0.52, green: 0.82, blue: 0.65)
            case "aurora":
                accent = Color(red: 0.64, green: 0.60, blue: 1.0)
                mint = Color(red: 0.48, green: 0.90, blue: 0.78)
            default:
                accent = Color(red: 0.32, green: 0.80, blue: 0.99)
                mint = Color(red: 0.36, green: 0.89, blue: 0.70)
            }
        } else {
            accent = Color(red: 0.38, green: 0.66, blue: 1.0)
            mint = Color(red: 0.34, green: 0.84, blue: 0.62)
        }
        warning = Color(red: 1.0, green: 0.45, blue: 0.38)
    }
}

private func driveStatusText(isStale: Bool, isEnded: Bool, isRunning: Bool) -> String {
    if isStale { return "Data stale" }
    if isEnded { return "Completed" }
    return isRunning ? "Driving" : "Paused"
}

private func gpsStatusText(_ freshness: VeluraDriveActivityAttributes.ContentState.GPSFreshness) -> String {
    switch freshness {
    case .good: "GPS locked"
    case .searching: "Searching for GPS"
    case .stale: "GPS signal stale"
    case .unreliable: "GPS data unreliable"
    case .unavailable: "GPS unavailable"
    }
}

private func gpsShortText(_ freshness: VeluraDriveActivityAttributes.ContentState.GPSFreshness) -> String {
    switch freshness {
    case .good: "Locked"
    case .searching: "Searching"
    case .stale: "Stale"
    case .unreliable: "Unreliable"
    case .unavailable: "Unavailable"
    }
}

private func gpsStatusColor(
    _ freshness: VeluraDriveActivityAttributes.ContentState.GPSFreshness,
    palette: DrivePalette
) -> Color {
    switch freshness {
    case .good: palette.mint
    case .searching: palette.accent
    case .stale, .unavailable, .unreliable: palette.warning
    }
}

private func durationText(for state: VeluraDriveActivityAttributes.ContentState) -> Text {
    if state.isRunning && !state.isEnded {
        let anchor = state.updatedAt.addingTimeInterval(-max(0, state.elapsedSeconds))
        return Text(timerInterval: anchor...Date.distantFuture, countsDown: false, showsHours: true)
    }
    return Text(formattedDuration(state.elapsedSeconds))
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

private struct LockScreenDriveActivityView: View {
    let context: ActivityViewContext<VeluraDriveActivityAttributes>

    private var state: VeluraDriveActivityAttributes.ContentState { context.state }
    private var isStale: Bool { context.isStale && !state.isEnded }
    private var palette: DrivePalette {
        DrivePalette(theme: state.themeRawValue, mode: state.appearanceModeRawValue)
    }
    private var distanceUnit: String { state.usesMiles ? "mi" : "km" }
    private var speedUnit: String { state.usesMiles ? "mph" : "km/h" }
    private var conversion: Double { state.usesMiles ? 0.621371 : 1 }
    private var speed: Int { Int((state.speedKmh * conversion).rounded()) }
    private var topSpeed: Int { Int((state.topSpeedKmh * conversion).rounded()) }
    private var distanceText: String { String(format: "%.1f %@", state.distanceKm * conversion, distanceUnit) }
    private var progress: Double {
        guard state.dialMaximum > 0 else { return 0 }
        return min(max(state.speedKmh * conversion / state.dialMaximum, 0), 1)
    }
    private var displayScale: CGFloat {
        switch state.displayScaleRawValue {
        case "compact": 0.88
        case "prominent": 1.08
        default: 1
        }
    }
    private var statusText: String {
        driveStatusText(isStale: isStale, isEnded: state.isEnded, isRunning: state.isRunning)
    }
    private var statusColor: Color {
        if isStale { return palette.warning }
        return (state.isRunning && !state.isEnded) ? palette.mint : Color.secondary
    }
    private var speedCaption: String {
        if isStale { return "Last known speed" }
        return state.isEnded ? "Final speed" : "Current speed"
    }
    private var gpsColor: Color {
        gpsStatusColor(state.gpsFreshness, palette: palette)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(speed)")
                    .font(.system(size: 40 * displayScale, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(isStale ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(speedUnit)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 0) {
                    Text("Duration")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    durationText(for: state)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                }
            }

            ProgressView(value: progress)
                .tint(isStale ? palette.warning : palette.accent)

            HStack(alignment: .top, spacing: 8) {
                metric("Distance", value: Text(distanceText))
                metric("Top speed", value: Text("\(topSpeed) \(speedUnit)"))
                metric("GPS", value: Text(gpsShortText(state.gpsFreshness)), valueColor: gpsColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .activityBackgroundTint(.clear)
        .activitySystemActionForegroundColor(.white)
        .widgetURL(URL(string: "velura://drive/active"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Velura live drive. \(speedCaption) \(speed) \(speedUnit). Distance \(distanceText). Duration \(formattedDuration(state.elapsedSeconds)). Top speed \(topSpeed) \(speedUnit). \(gpsStatusText(state.gpsFreshness)). \(statusText)")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "car.side.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.accent)
            Text("Velura")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.primary)

            Spacer(minLength: 8)

            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(statusColor)
        }
    }

    private func metric(_ title: String, value: Text, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            value
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DynamicIslandDriveActivityView {
    let context: ActivityViewContext<VeluraDriveActivityAttributes>

    private var state: VeluraDriveActivityAttributes.ContentState { context.state }
    private var isStale: Bool { context.isStale && !state.isEnded }
    private var palette: DrivePalette {
        DrivePalette(theme: state.themeRawValue, mode: state.appearanceModeRawValue)
    }
    private var speedUnit: String { state.usesMiles ? "mph" : "km/h" }
    private var distanceUnit: String { state.usesMiles ? "mi" : "km" }
    private var conversion: Double { state.usesMiles ? 0.621371 : 1 }
    private var speed: Int { Int((state.speedKmh * conversion).rounded()) }
    private var topSpeed: Int { Int((state.topSpeedKmh * conversion).rounded()) }
    private var distanceText: String { String(format: "%.1f %@", state.distanceKm * conversion, distanceUnit) }
    private var displayScale: CGFloat {
        switch state.displayScaleRawValue {
        case "compact": 0.92
        case "prominent": 1.08
        default: 1
        }
    }
    private var gpsColor: Color {
        gpsStatusColor(state.gpsFreshness, palette: palette)
    }

    var body: DynamicIsland {
        let palette = self.palette
        return DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(driveStatusText(isStale: isStale, isEnded: state.isEnded, isRunning: state.isRunning))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(isStale ? palette.warning : Color.primary)
                    Text("Velura")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 4)
            }
            DynamicIslandExpandedRegion(.trailing) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(speed)")
                        .font(.system(size: 26 * displayScale, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(isStale ? Color.secondary : Color.primary)
                    Text(speedUnit)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 4)
            }
            DynamicIslandExpandedRegion(.bottom) {
                HStack(alignment: .top, spacing: 8) {
                    islandMetric("Distance", value: Text(distanceText))
                    islandMetric("Duration", value: durationText(for: state))
                    islandMetric("Top speed", value: Text("\(topSpeed) \(speedUnit)"))
                    islandMetric("GPS", value: Text(gpsShortText(state.gpsFreshness)), valueColor: gpsColor)
                }
                .padding(.top, 4)
            }
        } compactLeading: {
            Image(systemName: "car.side.fill")
                .foregroundStyle(isStale ? palette.warning : palette.accent)
        } compactTrailing: {
            Text("\(speed)")
                .font(.system(size: 14 * displayScale, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(isStale ? palette.warning : Color.primary)
        } minimal: {
            Image(systemName: isStale ? "exclamationmark.triangle.fill" : "car.side.fill")
                .foregroundStyle(isStale ? palette.warning : palette.accent)
        }
        .keylineTint(isStale ? palette.warning : palette.accent)
        .widgetURL(URL(string: "velura://drive/active"))
    }

    private func islandMetric(_ title: String, value: Text, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            value
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
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
