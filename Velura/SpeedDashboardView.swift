import SwiftUI

enum DashboardDisplayScale: String, CaseIterable, Identifiable, Hashable {
    case compact
    case standard
    case prominent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .standard: "Standard"
        case .prominent: "Prominent"
        }
    }

    var gaugeHeightMultiplier: CGFloat {
        switch self {
        case .compact: 0.86
        case .standard: 1
        case .prominent: 1.14
        }
    }

    var readoutMultiplier: CGFloat {
        switch self {
        case .compact: 0.86
        case .standard: 1
        case .prominent: 1.14
        }
    }
}

struct SpeedDashboardView: View {
    @ObservedObject private var appearance = AppAppearance.shared
    @ObservedObject private var dashboardLayout = AppDashboardLayout.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: SpeedometerModel

    let dialStyle: SpeedometerDialStyle
    let displayScale: DashboardDisplayScale
    let usesMiles: Bool
    let rangeMaximum: Double
    let showsGPSStatus: Bool
    let accelerationControls: AnyView
    let onResetRequested: () -> Void

    private var unit: String { usesMiles ? "mph" : "km/h" }
    private var distanceUnit: String { usesMiles ? "mi" : "km" }
    private var displayedSpeed: Double { usesMiles ? model.speedKmh * 0.621371 : model.speedKmh }
    private var displayedTopSpeed: Double { usesMiles ? model.topSpeedKmh * 0.621371 : model.topSpeedKmh }
    private var displayedDistance: Double { usesMiles ? model.distanceKm * 0.621371 : model.distanceKm }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 710
            let standardGaugeHeight = min(max(geometry.size.height * 0.39, 274), 360)
            let gaugeHeight = min(max(standardGaugeHeight * displayScale.gaugeHeightMultiplier, 220), 410)

            ZStack {
                SpeedometerStyle.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: compact ? 14 : 19) {
                        brandHeader
                        ForEach(dashboardLayout.moduleOrder) { module in
                            dashboardModule(module, gaugeHeight: gaugeHeight)
                                .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .bottom)), reduceMotion: reduceMotion))
                        }
                        accelerationControls
                    }
                    .padding(.horizontal, geometry.size.width < 380 ? 18 : 22)
                    .padding(.top, compact ? 2 : 12)
                    .padding(.bottom, 18)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                    .animation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion), value: dashboardLayout.visibleOptionalModules)
                    .animation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion), value: dashboardLayout.moduleOrder)
                }
            }
        }
    }

    @ViewBuilder
    private func dashboardModule(_ module: DashboardModule, gaugeHeight: CGFloat) -> some View {
        switch module {
        case .speed:
            SpeedometerGauge(
                speed: displayedSpeed,
                maximum: rangeMaximum,
                dialStyle: dialStyle,
                displayScale: displayScale,
                unit: unit,
                isOverspeed: model.isOverspeedWarningActive
            )
            .frame(height: gaugeHeight)
            .animation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion), value: displayScale)
            .accessibilityLabel("Current speed")
            .accessibilityValue("\(Int(displayedSpeed.rounded())) \(unit)")
        case .gpsStatus:
            if showsGPSStatus && dashboardLayout.isVisible(module) {
                gpsStatusPill
            }
        case .driveMetrics:
            if dashboardLayout.isVisible(module) {
                driveMetrics
            }
        case .sessionControls:
            sessionControls
        case .safetyNote:
            if dashboardLayout.isVisible(module) {
                safetyNote
            }
        }
    }

    private var brandHeader: some View {
        ZStack {
            Text("VELURA")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .tracking(5)
                .foregroundStyle(SpeedometerStyle.foreground.opacity(0.88))
                .accessibilityAddTraits(.isHeader)

            if model.hasUnfinishedSession {
                HStack {
                    Spacer()
                    Button(action: onResetRequested) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SpeedometerStyle.secondary)
                            .frame(width: 32, height: 32)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Reset drive statistics")
                }
            }
        }
        .frame(height: 36)
    }

    private var gpsStatusPill: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.hasGPSFix ? SpeedometerStyle.mint : Color.orange.opacity(0.9))
                .frame(width: 10, height: 10)
                .shadow(color: (model.hasGPSFix ? SpeedometerStyle.mint : Color.orange).opacity(0.5), radius: 5)

            Text(model.gpsStatusTitle)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(0.35)
                .foregroundStyle(SpeedometerStyle.foreground.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Rectangle()
                .fill(SpeedometerStyle.foreground.opacity(0.16))
                .frame(width: 1, height: 19)

            Text(gpsDetail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 10)
        .background(SpeedometerStyle.foreground.opacity(0.025), in: Capsule())
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.hasGPSFix)
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.authorizationStatus)
    }

    private var gpsDetail: String {
        if model.hasGPSFix {
            return "±\(Int(model.horizontalAccuracy.rounded())) m"
        }
        if model.gpsStatusDetail == "Allow location access in Settings" { return "Open Settings" }
        if model.gpsStatusDetail == "Start a session to connect GPS" { return "Stand by" }
        if model.locationUpdateFailed { return "Unavailable" }
        if model.isGPSFixStale { return "Stale · searching" }
        if model.isSessionActive { return "Searching" }
        return "Ready"
    }

    private var driveMetrics: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 0) {
                metric(title: "DISTANCE", value: "\(String(format: "%.1f", displayedDistance)) \(distanceUnit)")
                metricDivider
                metric(title: "TOP SPEED", value: "\(Int(displayedTopSpeed.rounded())) \(unit)")
                metricDivider
                metric(title: "DURATION", value: dashboardDuration(model.elapsedTime(at: context.date)))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 20)
            .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .transaction { transaction in
                transaction.animation = VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion)
            }
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(SpeedometerStyle.foreground.opacity(0.11))
            .frame(width: 1, height: 42)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(SpeedometerStyle.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(SpeedometerStyle.foreground)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 8)
        .accessibilityElement(children: .combine)
    }

    private var sessionControls: some View {
        VStack(spacing: 12) {
            Button {
                if model.isSessionActive {
                    model.pauseSession()
                } else {
                    model.startSession()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: model.isSessionActive ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(SpeedometerStyle.accent)

                    Text(primaryActionTitle)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 62)
                .contentShape(Rectangle())
                .glassEffect(.regular.tint(SpeedometerStyle.accent.opacity(0.23)).interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityHint(model.isSessionActive ? "Pauses GPS tracking and drive statistics" : "Starts or resumes GPS speed and trip tracking")

            if model.hasUnfinishedSession {
                Button {
                    model.finishSession()
                } label: {
                    Text("Finish")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 49)
                        .contentShape(Rectangle())
                        .glassEffect(.regular.interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Finish and save this drive")
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var primaryActionTitle: String {
        if model.isSessionActive { return "Pause drive" }
        if model.hasUnfinishedSession { return "Resume drive" }
        return "Start drive"
    }

    private var safetyNote: some View {
        Text("GPS SPEED IS AN ESTIMATE. DRIVE SAFELY.")
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .tracking(1.25)
            .foregroundStyle(SpeedometerStyle.secondary.opacity(0.62))
            .padding(.top, 1)
    }
}

private func dashboardDuration(_ duration: TimeInterval) -> String {
    let totalMinutes = max(0, Int(duration / 60))
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(totalMinutes) min"
}
