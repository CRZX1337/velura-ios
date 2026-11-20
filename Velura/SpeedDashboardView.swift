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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var controlsGlassNamespace
    @ObservedObject var model: SpeedometerModel

    let dialStyle: SpeedometerDialStyle
    let displayScale: DashboardDisplayScale
    let usesMiles: Bool
    let rangeMaximum: Double
    let showsGPSStatus: Bool
    let onResetRequested: () -> Void
    let onOpenActiveRoute: () -> Void
    let onOpenDriveMode: () -> Void

    private var unit: String { usesMiles ? "mph" : "km/h" }
    private var distanceUnit: String { usesMiles ? "mi" : "km" }
    private var displayedSpeed: Double { usesMiles ? model.displaySpeedKmh * 0.621371 : model.displaySpeedKmh }
    private var displayedTopSpeed: Double { usesMiles ? model.topSpeedKmh * 0.621371 : model.topSpeedKmh }
    private var displayedDistance: Double { usesMiles ? model.distanceKm * 0.621371 : model.distanceKm }
    private var speedIntensity: Double {
        guard rangeMaximum > 0 else { return 0 }
        return min(max(displayedSpeed / rangeMaximum, 0), 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            let compact = geometry.size.height < 710 || landscape
            let compactWidth = geometry.size.width < 380 || dynamicTypeSize.isAccessibilitySize
            let standardGaugeHeight = landscape
                ? min(max(geometry.size.height * 0.52, 190), 260)
                : min(max(geometry.size.height * 0.39, 235), 360)
            let gaugeHeight = min(
                max(standardGaugeHeight * displayScale.gaugeHeightMultiplier, landscape ? 180 : 210),
                landscape ? 310 : 410
            )

            ZStack {
                VeluraAmbientBackdrop(
                    intensity: speedIntensity,
                    isWarning: model.isOverspeedWarningActive,
                    isActive: model.isSessionActive
                )

                ScrollView(showsIndicators: false) {
                    VStack(spacing: compact ? 14 : 19) {
                        brandHeader
                        ForEach(dashboardLayout.moduleOrder) { module in
                            dashboardModule(module, gaugeHeight: gaugeHeight, compactWidth: compactWidth)
                                .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .bottom)), reduceMotion: reduceMotion))
                        }
                    }
                    .padding(.horizontal, geometry.size.width < 380 ? 16 : 22)
                    .padding(.top, compact ? 2 : 12)
                    .padding(.bottom, 18)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                    .animation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion), value: dashboardLayout.visibleOptionalModules)
                    .animation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion), value: dashboardLayout.moduleOrder)
                }
            }
        }
        .toolbar(.visible, for: .tabBar)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.isSessionActive)
    }

    @ViewBuilder
    private func dashboardModule(_ module: DashboardModule, gaugeHeight: CGFloat, compactWidth: Bool) -> some View {
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
                driveMetrics(compact: compactWidth)
            }
        case .sessionControls:
            sessionControls
        case .safetyNote:
            if dashboardLayout.isVisible(module) {
                safetyNote
            }
        }
    }

    @ViewBuilder
    private var brandHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            HStack {
                brandTitle
                Spacer(minLength: 8)
                if model.hasUnfinishedSession { resetDriveButton }
            }
            .frame(minHeight: 44)
        } else {
            ZStack {
                brandTitle
                if model.hasUnfinishedSession {
                    HStack {
                        Spacer()
                        resetDriveButton
                    }
                }
            }
            .frame(minHeight: 44)
        }
    }

    private var brandTitle: some View {
        Text("VELURA")
            .modifier(AdaptiveFont(size: 14, weight: .bold, design: .rounded))
            .tracking(5)
            .foregroundStyle(SpeedometerStyle.foreground.opacity(0.88))
            .accessibilityAddTraits(.isHeader)
    }

    private var resetDriveButton: some View {
        Button(action: onResetRequested) {
            Image(systemName: "arrow.counterclockwise")
                .modifier(AdaptiveFont(size: 12, weight: .semibold))
                .foregroundStyle(SpeedometerStyle.secondary)
                .frame(width: 44, height: 44)
                .veluraGlassCircle(interactive: true)
        }
        .buttonStyle(VeluraGlassPressButtonStyle())
        .transition(VeluraMotion.transition(.scale(scale: 0.85).combined(with: .opacity), reduceMotion: reduceMotion))
        .accessibilityLabel("Reset drive statistics")
    }

    private var gpsStatusPill: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(model.isGPSReadingReliable ? SpeedometerStyle.mint : Color.orange.opacity(0.9))
                            .frame(width: 10, height: 10)
                            .shadow(color: (model.isGPSReadingReliable ? SpeedometerStyle.mint : Color.orange).opacity(0.5), radius: 5)
                        Text(model.gpsStatusTitle)
                            .modifier(AdaptiveFont(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(SpeedometerStyle.foreground.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(gpsDetail)
                        .modifier(AdaptiveFont(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                        .padding(.leading, 20)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 10) {
                    Circle()
                        .fill(model.isGPSReadingReliable ? SpeedometerStyle.mint : Color.orange.opacity(0.9))
                        .frame(width: 10, height: 10)
                        .shadow(color: (model.isGPSReadingReliable ? SpeedometerStyle.mint : Color.orange).opacity(0.5), radius: 5)

                    Text(model.gpsStatusTitle)
                        .modifier(AdaptiveFont(size: 12, weight: .semibold, design: .rounded))
                        .tracking(0.35)
                        .foregroundStyle(SpeedometerStyle.foreground.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Rectangle()
                        .fill(SpeedometerStyle.foreground.opacity(0.16))
                        .frame(width: 1, height: 19)

                    Text(gpsDetail)
                        .modifier(AdaptiveFont(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 10)
        .veluraGlassCapsule()
        .accessibilityElement(children: .combine)
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.isGPSReadingReliable)
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.authorizationStatus)
    }

    private var gpsDetail: String {
        if model.isGPSReadingReliable {
            return "±\(Int(model.horizontalAccuracy.rounded())) m"
        }
        if model.gpsStatusDetail == "Allow location access in Settings" { return "Open Settings" }
        if model.gpsStatusDetail == "Start a session to connect GPS" { return "Stand by" }
        if model.locationUpdateFailed { return "Unavailable" }
        if let issue = model.gpsDataQualityIssue {
            switch issue {
            case .stale: return "Stale · searching"
            case .inaccurate: return "Poor accuracy"
            case .implausible: return "Outlier ignored"
            }
        }
        if model.isGPSFixStale { return "Stale · searching" }
        if model.isSessionActive { return "Searching" }
        return "Ready"
    }

    private func driveMetrics(compact: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Group {
                if compact {
                    VStack(alignment: .leading, spacing: 11) {
                        metric(title: "DISTANCE", value: "\(String(format: "%.1f", displayedDistance)) \(distanceUnit)")
                        Rectangle().fill(SpeedometerStyle.foreground.opacity(0.11)).frame(height: 1)
                        metric(title: "TOP SPEED", value: "\(Int(displayedTopSpeed.rounded())) \(unit)")
                        Rectangle().fill(SpeedometerStyle.foreground.opacity(0.11)).frame(height: 1)
                        metric(title: "DURATION", value: dashboardDuration(model.elapsedTime(at: context.date)))
                    }
                    .padding(.vertical, 15)
                } else {
                    HStack(spacing: 0) {
                        metric(title: "DISTANCE", value: "\(String(format: "%.1f", displayedDistance)) \(distanceUnit)")
                        metricDivider
                        metric(title: "TOP SPEED", value: "\(Int(displayedTopSpeed.rounded())) \(unit)")
                        metricDivider
                        metric(title: "DURATION", value: dashboardDuration(model.elapsedTime(at: context.date)))
                    }
                    .padding(.vertical, 20)
                }
            }
            .padding(.horizontal, 11)
            .veluraGlassCard(cornerRadius: 24)
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
                .modifier(AdaptiveFont(size: 9, weight: .bold, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(SpeedometerStyle.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(value)
                .modifier(AdaptiveFont(size: 19, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(SpeedometerStyle.foreground)
                .contentTransition(.numericText())
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 8)
        .accessibilityElement(children: .combine)
    }

    private var sessionControls: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                Button {
                    withAnimation(VeluraMotion.animation(VeluraMotion.morph, reduceMotion: reduceMotion)) {
                        if model.isSessionActive {
                            model.pauseSession()
                        } else {
                            model.startSession()
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: model.isSessionActive ? "pause.fill" : "play.fill")
                            .modifier(AdaptiveFont(size: 18, weight: .bold))
                            .foregroundStyle(SpeedometerStyle.accent)
                            .contentTransition(.symbolEffect(.replace))

                        Text(primaryActionTitle)
                            .modifier(AdaptiveFont(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(SpeedometerStyle.foreground)
                            .contentTransition(.opacity)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 62)
                    .contentShape(Capsule())
                    .veluraGlassCapsule(
                        tint: SpeedometerStyle.accent.opacity(0.24),
                        interactive: true
                    )
                    .glassEffectID("drive-primary-action", in: controlsGlassNamespace)
                }
                .buttonStyle(VeluraGlassPressButtonStyle())
                .disabled(model.isDriveStorageLoading || model.isFinishingSession)
                .accessibilityHint(model.isSessionActive ? "Pauses GPS tracking and drive statistics" : "Starts or resumes GPS speed and trip tracking")

                if model.hasUnfinishedSession && !model.isDriveStorageLoading {
                    Button(action: onOpenActiveRoute) {
                        Label("View live route", systemImage: "map")
                            .modifier(AdaptiveFont(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(SpeedometerStyle.accent)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 49)
                            .contentShape(Capsule())
                            .veluraGlassCapsule(interactive: true)
                            .glassEffectID("drive-live-route", in: controlsGlassNamespace)
                    }
                    .buttonStyle(VeluraGlassPressButtonStyle())
                    .disabled(model.isFinishingSession)
                    .transition(VeluraMotion.transition(.opacity.combined(with: .scale(scale: 0.96)), reduceMotion: reduceMotion))
                    .accessibilityHint("Opens the live route for this unfinished drive")
                }

                if model.hasUnfinishedSession {
                    Button {
                        withAnimation(VeluraMotion.animation(VeluraMotion.morph, reduceMotion: reduceMotion)) {
                            model.finishSession()
                        }
                    } label: {
                        Text(model.isFinishingSession ? "Saving…" : "Finish")
                            .modifier(AdaptiveFont(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(SpeedometerStyle.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 49)
                            .contentShape(Capsule())
                            .veluraGlassCapsule(interactive: true)
                            .glassEffectID("drive-finish", in: controlsGlassNamespace)
                    }
                    .buttonStyle(VeluraGlassPressButtonStyle())
                    .disabled(model.isFinishingSession)
                    .transition(VeluraMotion.transition(.opacity.combined(with: .scale(scale: 0.96)), reduceMotion: reduceMotion))
                    .accessibilityLabel("Finish and save this drive")
                }

                Button(action: onOpenDriveMode) {
                    HStack(spacing: 10) {
                        Image(systemName: "steeringwheel")
                            .modifier(AdaptiveFont(size: 15, weight: .semibold))
                            .foregroundStyle(SpeedometerStyle.accent)
                        Text("Drive Mode")
                            .modifier(AdaptiveFont(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(SpeedometerStyle.foreground)
                        Spacer()
                        Text("Cockpit & Nav")
                            .modifier(AdaptiveFont(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(SpeedometerStyle.secondary)
                        Image(systemName: "chevron.right")
                            .modifier(AdaptiveFont(size: 11, weight: .semibold))
                            .foregroundStyle(SpeedometerStyle.secondary)
                    }
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 49)
                    .contentShape(Capsule())
                    .veluraGlassCapsule(interactive: true)
                    .glassEffectID("drive-mode-entry", in: controlsGlassNamespace)
                }
                .buttonStyle(VeluraGlassPressButtonStyle())
                .accessibilityLabel("Open Drive Mode cockpit and in-app navigation")
            }
        }
        .animation(VeluraMotion.animation(VeluraMotion.morph, reduceMotion: reduceMotion), value: model.hasUnfinishedSession)
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.isSessionActive)
    }

    private var primaryActionTitle: String {
        if model.isDriveStorageLoading { return "Restoring drive data" }
        if model.isFinishingSession { return "Saving drive" }
        if model.isSessionActive { return "Pause drive" }
        if model.hasUnfinishedSession { return "Resume drive" }
        return "Start drive"
    }

    private var safetyNote: some View {
        Text("GPS SPEED IS AN ESTIMATE. DRIVE SAFELY.")
            .modifier(AdaptiveFont(size: 9, weight: .semibold, design: .rounded))
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
