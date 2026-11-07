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

private struct LockScreenDriveActivityView: View {
    let context: ActivityViewContext<VeluraDriveActivityAttributes>
    @Environment(\.colorScheme) private var colorScheme

    private var state: VeluraDriveActivityAttributes.ContentState { context.state }
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
    private var elapsedAnchor: Date {
        state.updatedAt.addingTimeInterval(-max(0, state.elapsedSeconds))
    }
    private var speed: Int { Int((state.speedKmh * conversion).rounded()) }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.accent)
                    .frame(width: 30, height: 30)
                    .background(colors.accent.opacity(0.13), in: Circle())

                VStack(alignment: .leading, spacing: 1) {
                    Text("VELURA")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(colors.foreground)
                    Text("LIVE DRIVE")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(colors.secondary)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Circle()
                        .fill(state.isEnded ? colors.secondary : colors.mint)
                        .frame(width: 7, height: 7)
                    Text(state.isEnded ? "COMPLETE" : (state.isRunning ? "DRIVING" : "PAUSED"))
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(0.45)
                        .foregroundStyle(colors.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(colors.foreground.opacity(0.055), in: Capsule())
            }

            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(speed)")
                            .font(.system(size: 43 * displayScale, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(colors.foreground)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Text(speedUnit)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(colors.secondary)
                    }
                    Text(state.isEnded ? "FINAL SPEED" : "CURRENT SPEED")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .tracking(1.05)
                        .foregroundStyle(colors.secondary)
                    DriveGaugeMark(
                        progress: progress,
                        dialStyle: state.dialStyleRawValue,
                        accent: colors.accent,
                        secondary: colors.secondary,
                        mint: colors.mint
                    )
                    .frame(width: 105, height: 17, alignment: .leading)
                    .padding(.top, 3)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 12) {
                    sideMetric(
                        title: "DISTANCE",
                        value: String(format: "%.1f %@", state.distanceKm * conversion, distanceUnit)
                    )
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("DURATION")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .tracking(0.75)
                            .foregroundStyle(colors.secondary)
                        if state.isRunning && !state.isEnded {
                            Text(timerInterval: elapsedAnchor...Date.distantFuture, countsDown: false, showsHours: true)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(colors.foreground)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        } else {
                            Text(formattedDuration(state.elapsedSeconds))
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(colors.foreground)
                        }
                    }
                }
            }

            Rectangle()
                .fill(colors.secondary.opacity(0.2))
                .frame(height: 1)

            HStack(spacing: 8) {
                Circle()
                    .fill(gpsColor)
                    .frame(width: 7, height: 7)
                Text(gpsText)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(colors.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                Text("TOP SPEED")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(0.55)
                    .foregroundStyle(colors.secondary)
                Text("\(Int((state.topSpeedKmh * conversion).rounded())) \(speedUnit)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(colors.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .activityBackgroundTint(colors.background)
        .activitySystemActionForegroundColor(colors.foreground)
        .widgetURL(URL(string: "velura://drive/active"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Velura live drive. Current speed \(speed) \(speedUnit), distance \(String(format: "%.1f", state.distanceKm * conversion)) \(distanceUnit), duration \(formattedDuration(state.elapsedSeconds)), top speed \(Int((state.topSpeedKmh * conversion).rounded())) \(speedUnit), GPS \(gpsText.lowercased())")
    }

    private var gpsColor: Color {
        switch state.gpsFreshness {
        case .good: colors.mint
        case .searching: colors.accent
        case .stale, .unavailable, .unreliable: colors.warning
        }
    }

    private var gpsText: String {
        switch state.gpsFreshness {
        case .good: "GPS LOCKED"
        case .searching: "SEARCHING FOR GPS"
        case .stale: "GPS SIGNAL STALE"
        case .unreliable: "GPS DATA UNRELIABLE"
        case .unavailable: "GPS UNAVAILABLE"
        }
    }

    private func sideMetric(title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.75)
                .foregroundStyle(colors.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(colors.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct DriveGaugeMark: View {
    let progress: Double
    let dialStyle: String
    let accent: Color
    let secondary: Color
    let mint: Color

    private var boundedProgress: Double { min(max(progress, 0), 1) }

    @ViewBuilder
    var body: some View {
        switch dialStyle {
        case "digitalHUD":
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(secondary.opacity(0.18))
                    Capsule().fill(accent).frame(width: geometry.size.width * boundedProgress)
                }
            }
            .frame(height: 5)
        case "verticalBar":
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<12, id: \.self) { index in
                    let isActive = Double(index) / 12 < boundedProgress
                    Capsule()
                        .fill(isActive ? accent : secondary.opacity(0.2))
                        .frame(width: 4, height: CGFloat(5 + (index % 4) * 2))
                }
            }
            .frame(height: 15, alignment: .bottom)
        case "segmentedLED", "segmentedRing", "sport":
            HStack(spacing: 3) {
                ForEach(0..<14, id: \.self) { index in
                    let isActive = Double(index) / 14 < boundedProgress
                    let color = dialStyle == "sport" && index >= 11 ? Color(red: 1, green: 0.34, blue: 0.31) : accent
                    Capsule()
                        .fill(isActive ? color : secondary.opacity(0.2))
                        .frame(width: 5, height: dialStyle == "sport" ? 7 : 5)
                }
            }
            .frame(height: 15)
        case "fullCircle", "twinRing":
            ZStack {
                Circle().stroke(secondary.opacity(0.2), lineWidth: 2.2)
                Circle()
                    .trim(from: 0, to: boundedProgress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if dialStyle == "twinRing" {
                    Circle()
                        .trim(from: 0, to: boundedProgress)
                        .stroke(mint, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .padding(4)
                        .rotationEffect(.degrees(-90))
                }
            }
            .frame(width: 16, height: 16)
        default:
            DriveGaugeArc(progress: boundedProgress)
                .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 35, height: 17)
        }
    }
}

private struct DriveGaugeArc: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.44
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(150),
            endAngle: .degrees(150 + 240 * min(max(progress, 0), 1)),
            clockwise: false
        )
        return path
    }
}

private struct DynamicIslandDriveActivityView {
    let context: ActivityViewContext<VeluraDriveActivityAttributes>

    private var state: VeluraDriveActivityAttributes.ContentState { context.state }
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
    private var elapsedAnchor: Date { state.updatedAt.addingTimeInterval(-max(0, state.elapsedSeconds)) }
    private var speed: Int { Int((state.speedKmh * conversion).rounded()) }
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
                HStack(spacing: 7) {
                    Image(systemName: driveDialSymbol(state.dialStyleRawValue))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VELURA")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(palette.secondary)
                        Text(state.isEnded ? "DRIVE COMPLETE" : (state.isRunning ? "DRIVE ACTIVE" : "DRIVE PAUSED"))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.foreground)
                    }
                }
            }
            DynamicIslandExpandedRegion(.trailing) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(speed)")
                        .font(.system(size: 23 * displayScale, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(palette.foreground)
                    Text(speedUnit)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.secondary)
                }
            }
            DynamicIslandExpandedRegion(.bottom) {
                VStack(spacing: 10) {
                    Rectangle()
                        .fill(palette.secondary.opacity(0.23))
                        .frame(height: 1)
                    HStack(spacing: 0) {
                        islandMetric("DISTANCE", value: String(format: "%.1f %@", state.distanceKm * conversion, distanceUnit), colors: palette)
                        islandDurationMetric(colors: palette)
                        islandMetric("TOP SPEED", value: "\(Int((state.topSpeedKmh * conversion).rounded())) \(speedUnit)", colors: palette)
                    }
                    HStack(spacing: 6) {
                        Circle().fill(gpsColor).frame(width: 7, height: 7)
                        Text(gpsText)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(palette.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 6)
            }
        } compactLeading: {
            Image(systemName: driveDialSymbol(state.dialStyleRawValue))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.accent)
        } compactTrailing: {
            HStack(spacing: 2) {
                Text("\(speed)")
                    .font(.system(size: 13 * displayScale, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(speedUnit)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.secondary)
            }
            .foregroundStyle(palette.foreground)
        } minimal: {
            Image(systemName: driveDialSymbol(state.dialStyleRawValue))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.accent)
        }
        .keylineTint(palette.accent)
        .widgetURL(URL(string: "velura://drive/active"))
    }

    private var gpsColor: Color {
        switch state.gpsFreshness {
        case .good: colors.mint
        case .searching: colors.accent
        case .stale, .unavailable, .unreliable: colors.warning
        }
    }

    private var gpsText: String {
        switch state.gpsFreshness {
        case .good: "GPS LOCKED"
        case .searching: "SEARCHING FOR GPS"
        case .stale: "GPS SIGNAL STALE"
        case .unreliable: "GPS DATA UNRELIABLE"
        case .unavailable: "GPS UNAVAILABLE"
        }
    }

    private func islandDurationMetric(colors: LiveActivityColors) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("DURATION")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(colors.secondary)
            Group {
                if state.isRunning && !state.isEnded {
                    Text(timerInterval: elapsedAnchor...Date.distantFuture, countsDown: false, showsHours: true)
                } else {
                    Text(formattedDuration(state.elapsedSeconds))
                }
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(colors.foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func islandMetric(_ title: String, value: String, colors: LiveActivityColors) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(colors.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(colors.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func driveDialSymbol(_ rawValue: String) -> String {
    switch rawValue {
    case "sport": "gauge.with.dots.needle.67percent"
    case "digitalHUD": "waveform.path"
    case "verticalBar": "chart.bar.fill"
    case "segmentedLED", "segmentedRing": "circle.dotted"
    case "twinRing", "fullCircle": "circle.circle"
    default: "speedometer"
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
