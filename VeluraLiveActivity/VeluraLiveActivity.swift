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

private struct LiveActivityColors {
    let background: Color
    let foreground: Color
    let secondary: Color
    let accent: Color
    let mint: Color
    let warning: Color

    init(theme: String, mode: String, colorScheme: ColorScheme, island: Bool = false) {
        if mode == "palette" {
            switch theme {
            case "ocean":
                background = Color(red: 0.018, green: 0.070, blue: 0.078)
                foreground = .white
                secondary = Color(red: 0.66, green: 0.77, blue: 0.75)
                accent = Color(red: 0.24, green: 0.86, blue: 0.75)
                mint = Color(red: 0.48, green: 0.92, blue: 0.70)
            case "graphite":
                background = Color(red: 0.055, green: 0.058, blue: 0.067)
                foreground = .white
                secondary = Color(red: 0.72, green: 0.73, blue: 0.76)
                accent = Color(red: 1.0, green: 0.69, blue: 0.28)
                mint = Color(red: 0.52, green: 0.88, blue: 0.65)
            case "forest":
                background = Color(red: 0.027, green: 0.078, blue: 0.059)
                foreground = Color(red: 0.92, green: 0.96, blue: 0.93)
                secondary = Color(red: 0.66, green: 0.76, blue: 0.69)
                accent = Color(red: 0.30, green: 0.82, blue: 0.52)
                mint = Color(red: 0.70, green: 0.88, blue: 0.58)
            case "ember":
                background = Color(red: 0.078, green: 0.067, blue: 0.063)
                foreground = Color(red: 0.96, green: 0.93, blue: 0.87)
                secondary = Color(red: 0.76, green: 0.70, blue: 0.63)
                accent = Color(red: 0.83, green: 0.48, blue: 0.27)
                mint = Color(red: 0.48, green: 0.79, blue: 0.67)
            case "aurora":
                background = Color(red: 0.045, green: 0.043, blue: 0.105)
                foreground = Color(red: 0.95, green: 0.94, blue: 1.0)
                secondary = Color(red: 0.72, green: 0.70, blue: 0.85)
                accent = Color(red: 0.57, green: 0.52, blue: 0.99)
                mint = Color(red: 0.48, green: 0.91, blue: 0.80)
            default:
                background = Color(red: 0.025, green: 0.043, blue: 0.067)
                foreground = .white
                secondary = Color(red: 0.63, green: 0.70, blue: 0.77)
                accent = Color(red: 0.27, green: 0.79, blue: 0.98)
                mint = Color(red: 0.34, green: 0.91, blue: 0.73)
            }
            warning = Color(red: 1.0, green: 0.34, blue: 0.31)
            return
        }

        let wantsLight = mode == "light" || (mode == "system" && colorScheme == .light)
        let useLight = wantsLight && !island
        if useLight {
            background = Color(red: 0.96, green: 0.97, blue: 0.985)
            foreground = Color(red: 0.10, green: 0.12, blue: 0.15)
            secondary = Color(red: 0.34, green: 0.37, blue: 0.41)
            accent = Color(red: 0.10, green: 0.38, blue: 0.75)
            mint = Color(red: 0.10, green: 0.46, blue: 0.33)
            warning = Color(red: 0.72, green: 0.16, blue: 0.13)
        } else {
            background = Color(red: 0.035, green: 0.039, blue: 0.047)
            foreground = .white
            secondary = Color(red: 0.66, green: 0.69, blue: 0.73)
            accent = Color(red: 0.29, green: 0.57, blue: 0.98)
            mint = Color(red: 0.32, green: 0.84, blue: 0.63)
            warning = Color(red: 1.0, green: 0.36, blue: 0.33)
        }
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
    colors: LiveActivityColors
) -> Color {
    switch freshness {
    case .good: colors.mint
    case .searching: colors.accent
    case .stale, .unavailable, .unreliable: colors.warning
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
    return String(format: "%d:%02d:%02d", hours, minutes, seconds)
}

private struct LockScreenDriveActivityView: View {
    let context: ActivityViewContext<VeluraDriveActivityAttributes>
    @Environment(\.colorScheme) private var colorScheme

    private var state: VeluraDriveActivityAttributes.ContentState { context.state }
    private var isStale: Bool { context.isStale && !state.isEnded }
    private var colors: LiveActivityColors {
        LiveActivityColors(
            theme: state.themeRawValue,
            mode: state.appearanceModeRawValue,
            colorScheme: colorScheme
        )
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
        case "prominent": 1.12
        default: 1
        }
    }
    private var speedCaption: String {
        if isStale { return "Last known speed" }
        return state.isEnded ? "Final speed" : "Current speed"
    }
    private var statusColor: Color {
        if isStale { return colors.warning }
        if state.isRunning && !state.isEnded { return colors.mint }
        return colors.secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "car.side.fill")
                        .foregroundStyle(colors.accent)
                    Text("Velura")
                        .foregroundStyle(colors.foreground)
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(driveStatusText(isStale: isStale, isEnded: state.isEnded, isRunning: state.isRunning))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(statusColor)
                }
            }

            HStack(alignment: .bottom, spacing: 12) {
                speedReadout
                Spacer(minLength: 8)
                metric("Duration", value: durationText(for: state), alignment: .trailing)
            }

            ProgressView(value: progress)
                .tint(isStale ? colors.warning : colors.accent)

            HStack(alignment: .top, spacing: 8) {
                metric("Distance", value: Text(distanceText))
                    .frame(maxWidth: .infinity, alignment: .leading)
                metric("Top speed", value: Text("\(topSpeed) \(speedUnit)"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                metric(
                    "GPS",
                    value: Text(gpsShortText(state.gpsFreshness)),
                    valueColor: gpsStatusColor(state.gpsFreshness, colors: colors),
                    alignment: .trailing
                )
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .activityBackgroundTint(colors.background)
        .activitySystemActionForegroundColor(colors.foreground)
        .widgetURL(URL(string: "velura://drive/active"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Velura live drive. \(speedCaption) \(speed) \(speedUnit). Distance \(distanceText). Duration \(formattedDuration(state.elapsedSeconds)). Top speed \(topSpeed) \(speedUnit). \(gpsStatusText(state.gpsFreshness)). \(driveStatusText(isStale: isStale, isEnded: state.isEnded, isRunning: state.isRunning))")
    }

    private var speedReadout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(speed)")
                    .font(.system(size: 42 * displayScale, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(isStale ? colors.secondary : colors.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(speedUnit)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(colors.secondary)
            }

            Text(speedCaption)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(colors.secondary)
        }
    }

    private func metric(
        _ title: String,
        value: Text,
        valueColor: Color? = nil,
        alignment: HorizontalAlignment = .leading
    ) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(colors.secondary)
            value
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(valueColor ?? colors.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct DynamicIslandDriveActivityView {
    let context: ActivityViewContext<VeluraDriveActivityAttributes>

    private var state: VeluraDriveActivityAttributes.ContentState { context.state }
    private var isStale: Bool { context.isStale && !state.isEnded }
    private var colors: LiveActivityColors {
        LiveActivityColors(
            theme: state.themeRawValue,
            mode: state.appearanceModeRawValue,
            colorScheme: .dark,
            island: true
        )
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

    var body: DynamicIsland {
        let palette = colors
        return DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(driveStatusText(isStale: isStale, isEnded: state.isEnded, isRunning: state.isRunning))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(isStale ? palette.warning : palette.foreground)
                    Text("Velura")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.secondary)
                }
                .padding(.leading, 4)
            }
            DynamicIslandExpandedRegion(.trailing) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(speed)")
                        .font(.system(size: 28 * displayScale, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(isStale ? palette.secondary : palette.foreground)
                    Text(speedUnit)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.secondary)
                }
                .padding(.trailing, 4)
            }
            DynamicIslandExpandedRegion(.bottom) {
                VStack(spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        islandMetric("Distance", value: Text(distanceText), colors: palette)
                        islandMetric("Duration", value: durationText(for: state), colors: palette)
                        islandMetric("Top speed", value: Text("\(topSpeed) \(speedUnit)"), colors: palette)
                    }
                    HStack(spacing: 6) {
                        Circle()
                            .fill(gpsStatusColor(state.gpsFreshness, colors: palette))
                            .frame(width: 6, height: 6)
                        Text(gpsStatusText(state.gpsFreshness))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
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
                .foregroundStyle(isStale ? palette.warning : palette.foreground)
        } minimal: {
            Image(systemName: isStale ? "exclamationmark.triangle.fill" : "car.side.fill")
                .foregroundStyle(isStale ? palette.warning : palette.accent)
        }
        .keylineTint(isStale ? palette.warning : palette.accent)
        .widgetURL(URL(string: "velura://drive/active"))
    }

    private func islandMetric(_ title: String, value: Text, colors: LiveActivityColors) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(colors.secondary)
            value
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(colors.foreground)
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
