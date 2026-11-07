import SwiftUI
import UIKit

enum SpeedometerStyle {
    static var background: Color { AppAppearance.shared.background }
    static var foreground: Color { AppAppearance.shared.foreground }
    static var secondary: Color { AppAppearance.shared.secondary }
    static var accent: Color { AppAppearance.shared.accent }
    static var accentForeground: Color { AppAppearance.shared.accentForeground }
    static var mint: Color { AppAppearance.shared.mint }
    static var warning: Color { AppAppearance.shared.warning }
}

private enum MainTab: Hashable {
    case speedometer
    case acceleration
    case history
    case settings
}

struct ContentView: View {
    @ObservedObject private var appearance = AppAppearance.shared
    @ObservedObject private var dashboardLayout = AppDashboardLayout.shared
    @StateObject private var model = SpeedometerModel()
    @AppStorage("speedometer.selectedRange") private var selectedRange = 50
    @AppStorage("speedometer.customRange") private var customRange = 160
    @AppStorage("speedometer.usesMiles") private var usesMiles = false
    @AppStorage("speedometer.dashboard.displayScale") private var dashboardDisplayScaleRawValue = DashboardDisplayScale.standard.rawValue
    @AppStorage("speedometer.showsGPSStatus") private var showsGPSStatus = true
    @AppStorage("speedometer.overspeed.enabled") private var overspeedWarningEnabled = false
    @AppStorage("speedometer.overspeed.thresholdKmh") private var overspeedThresholdKmh = 100.0
    @AppStorage("speedometer.firstLaunchSetup.completed") private var hasCompletedFirstLaunchSetup = false
    @State private var showingResetConfirmation = false
    @State private var selectedTab: MainTab = .speedometer
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var unit: String { usesMiles ? "mph" : "km/h" }
    private var unitConversion: Double { usesMiles ? 0.621371 : 1 }
    private var displayedSpeed: Double { usesMiles ? model.speedKmh * 0.621371 : model.speedKmh }
    private func displayedSpeed(for speedKmh: Double) -> Double { speedKmh * unitConversion }
    private var rangeMaximum: Double { Double(selectedRange == -1 ? customRange : selectedRange) }
    private var displayedWarningThreshold: Double { usesMiles ? overspeedThresholdKmh * 0.621371 : overspeedThresholdKmh }
    private var gaugePreviewProgress: Double {
        guard rangeMaximum > 0 else { return 0 }
        return min(max(displayedSpeed / rangeMaximum, 0), 1)
    }
    private var warningThresholdRange: ClosedRange<Double> {
        let conversion = usesMiles ? 0.621371 : 1.0
        return (20.0 * conversion)...(240.0 * conversion)
    }

    var body: some View {
        Group {
            if hasCompletedFirstLaunchSetup {
                mainTabInterface
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .trailing)))
            } else {
                FirstLaunchSetupView(model: model, onContinue: completeFirstLaunchSetup)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .leading)))
            }
        }
        .animation(VeluraMotion.animation(VeluraMotion.tabChange, reduceMotion: reduceMotion), value: hasCompletedFirstLaunchSetup)
    }

    private func completeFirstLaunchSetup() {
        hasCompletedFirstLaunchSetup = true
    }

    private var speedWarningIcon: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .modifier(AdaptiveFont(size: 17, weight: .semibold))
            .foregroundStyle(SpeedometerStyle.warning)
            .symbolEffect(.pulse, options: .repeating, isActive: model.isOverspeedWarningActive && !reduceMotion)
    }

    private var speedWarningDetails: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("SPEED WARNING")
                .modifier(AdaptiveFont(size: 10, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(SpeedometerStyle.warning)
            Text("Limit \(Int(displayedWarningThreshold.rounded())) \(unit)")
                .modifier(AdaptiveFont(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.foreground.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var speedWarningValue: some View {
        Text("\(Int(displayedSpeed.rounded())) \(unit)")
            .modifier(AdaptiveFont(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(SpeedometerStyle.foreground)
            .contentTransition(.numericText())
            .fixedSize(horizontal: false, vertical: true)
    }

    private var mainTabInterface: some View {
        TabView(selection: $selectedTab) {
            speedometerScreen
                .tabItem { Label("Speed", systemImage: "speedometer") }
                .tag(MainTab.speedometer)

            accelerationScreen
                .tabItem { Label("Test", systemImage: "stopwatch") }
                .tag(MainTab.acceleration)

            NavigationStack {
                DriveHistoryView()
            }
            .tabItem { Label("Drives", systemImage: "clock.arrow.circlepath") }
            .tag(MainTab.history)

            NavigationStack {
                settingsScreen
            }
            .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
            .tag(MainTab.settings)
        }
        .tint(SpeedometerStyle.accent)
        .toolbar(.visible, for: .tabBar)
        .tabBarMinimizeBehavior(.never)
        .animation(VeluraMotion.animation(VeluraMotion.tabChange, reduceMotion: reduceMotion), value: selectedTab)
        .preferredColorScheme(appearance.preferredColorScheme)
        .safeAreaInset(edge: .top, spacing: 0) {
            if model.isOverspeedWarningActive {
                speedWarningBanner
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .transition(VeluraMotion.transition(.move(edge: .top).combined(with: .opacity), reduceMotion: reduceMotion))
            }
        }
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.isOverspeedWarningActive)
        .onAppear(perform: syncOverspeedWarning)
        .onChange(of: overspeedWarningEnabled) { _, _ in syncOverspeedWarning() }
        .onChange(of: overspeedThresholdKmh) { _, _ in syncOverspeedWarning() }
        .alert("Location access is off", isPresented: $model.showLocationAlert) {
            Button("Open Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    openURL(settingsURL)
                }
            }
            Button("Not now", role: .cancel) { }
        } message: {
            Text("Allow location access in Settings to measure your live speed and trip distance.")
        }
    }

    private func syncOverspeedWarning() {
        model.configureOverspeedWarning(enabled: overspeedWarningEnabled, thresholdKmh: overspeedThresholdKmh)
    }

    @ViewBuilder
    private var speedWarningBanner: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        speedWarningIcon
                        speedWarningDetails
                    }
                    speedWarningValue
                }
            } else {
                HStack(spacing: 11) {
                    speedWarningIcon
                    speedWarningDetails
                    Spacer(minLength: 8)
                    speedWarningValue
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(SpeedometerStyle.warning.opacity(0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .glassEffect(.regular.tint(SpeedometerStyle.warning.opacity(0.2)), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(SpeedometerStyle.warning.opacity(0.32), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var speedometerScreen: some View {
        SpeedDashboardView(
            model: model,
            dialStyle: appearance.dialStyle,
            displayScale: DashboardDisplayScale(rawValue: dashboardDisplayScaleRawValue) ?? .standard,
            usesMiles: usesMiles,
            rangeMaximum: rangeMaximum,
            showsGPSStatus: showsGPSStatus,
            onResetRequested: { showingResetConfirmation = true }
        )
        .confirmationDialog("Reset this drive?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
            Button("Reset drive", role: .destructive) {
                withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) { model.resetSession() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your top speed, distance and drive time will be cleared.")
        }
    }

    private var accelerationScreen: some View {
        AccelerationTestView(model: model)
    }

    private var settingsScreen: some View {
        GeometryReader { geometry in
            ZStack {
                SpeedometerStyle.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        pageHeader(title: "Settings", subtitle: "Personalize your speedometer")
                        unitSetting
                        speedWarningSetting
                        gpsStatusSetting
                        rangePicker
                        dashboardDisplayScaleSetting
                        appearanceSection
                        DashboardLayoutSettingsSection(layout: dashboardLayout)
                    }
                    .padding(.horizontal, geometry.size.width < 380 ? 16 : 22)
                    .padding(.top, 14)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .toolbar(.visible, for: .tabBar)
    }

    private var dashboardDisplayScaleSetting: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .modifier(AdaptiveFont(size: 15, weight: .semibold))
                    .foregroundStyle(SpeedometerStyle.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dashboard display")
                        .modifier(AdaptiveFont(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                    Text("Scale the gauge and speed readout")
                        .modifier(AdaptiveFont(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                }
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    Picker("Dashboard scale", selection: $dashboardDisplayScaleRawValue) {
                        ForEach(DashboardDisplayScale.allCases) { scale in
                            Text(scale.title).tag(scale.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    Picker("Dashboard scale", selection: $dashboardDisplayScaleRawValue) {
                        ForEach(DashboardDisplayScale.allCases) { scale in
                            Text(scale.title).tag(scale.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .accessibilityLabel("Dashboard display scale")

            Text("Controls and trip metrics stay full size.")
                .modifier(AdaptiveFont(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.secondary)
        }
        .padding(15)
        .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 21))
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 10) {
                Image(systemName: "paintpalette.fill")
                    .modifier(AdaptiveFont(size: 15, weight: .semibold))
                    .foregroundStyle(SpeedometerStyle.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Appearance")
                        .modifier(AdaptiveFont(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                    Text("Choose an appearance and dial style")
                        .modifier(AdaptiveFont(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("APPEARANCE MODE")
                    .modifier(AdaptiveFont(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(SpeedometerStyle.secondary)
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        Picker("Appearance mode", selection: $appearance.appearanceMode) {
                            ForEach(AppAppearanceMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                    } else {
                        Picker("Appearance mode", selection: $appearance.appearanceMode) {
                            ForEach(AppAppearanceMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .accessibilityLabel("Appearance mode")
                Text(appearance.appearanceMode == .palette
                     ? "Using the \(appearance.theme.title) palette."
                     : "Using the \(appearance.appearanceMode.title.lowercased()) appearance.")
                    .modifier(AdaptiveFont(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("CURATED PALETTE")
                    .modifier(AdaptiveFont(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(SpeedometerStyle.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 190 : 92), spacing: 8)], spacing: 8) {
                    ForEach(AppearanceTheme.allCases) { theme in
                        themeOption(theme)
                    }
                }
            }

            Rectangle()
                .fill(SpeedometerStyle.foreground.opacity(0.1))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 9) {
                Text("SPEEDOMETER DIAL")
                    .modifier(AdaptiveFont(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(SpeedometerStyle.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 200 : 104), spacing: 8)], spacing: 8) {
                    ForEach(SpeedometerDialStyle.allCases) { style in
                        dialOption(style)
                    }
                }
            }
        }
        .padding(15)
        .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 21))
    }

    private func themeOption(_ theme: AppearanceTheme) -> some View {
        let isSelected = appearance.appearanceMode == .palette && appearance.theme == theme
        return Button {
            withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                appearance.theme = theme
                appearance.appearanceMode = .palette
            }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                themePreview(theme)
                    .dynamicTypeSize(.large)
                    .frame(height: 58)
                HStack(alignment: .top, spacing: 3) {
                    Text(theme.title)
                        .modifier(AdaptiveFont(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .modifier(AdaptiveFont(size: 10, weight: .semibold))
                            .foregroundStyle(theme.accent)
                    }
                }
            }
            .padding(7)
            .frame(maxWidth: .infinity)
            .background(isSelected ? theme.accent.opacity(0.1) : SpeedometerStyle.foreground.opacity(0.02), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? theme.accent.opacity(0.72) : SpeedometerStyle.foreground.opacity(0.08), lineWidth: isSelected ? 1.2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.title) app theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func themePreview(_ theme: AppearanceTheme) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.background)
            GaugeArc(progress: 1)
                .stroke(theme.foreground.opacity(0.16), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 55, height: 52)
                .offset(y: 7)
            GaugeArc(progress: gaugePreviewProgress)
                .stroke(theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 55, height: 52)
                .offset(y: 7)
            VStack(spacing: -2) {
                Text(String(format: "%.0f", displayedSpeed))
                    .modifier(AdaptiveFont(size: 14, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(theme.foreground)
                Text(unit)
                    .modifier(AdaptiveFont(size: 6, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.secondary)
            }
            .offset(y: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topLeading) {
            Circle()
                .fill(theme.mint)
                .frame(width: 5, height: 5)
                .shadow(color: theme.mint.opacity(0.6), radius: 3)
                .padding(6)
        }
    }

    private func dialOption(_ style: SpeedometerDialStyle) -> some View {
        let isSelected = appearance.dialStyle == style
        return Button {
            withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) { appearance.dialStyle = style }
        } label: {
            VStack(spacing: 5) {
                dialPreview(style)
                    .dynamicTypeSize(.large)
                    .frame(height: 47)
                HStack(alignment: .top, spacing: 3) {
                    Text(style.title)
                        .modifier(AdaptiveFont(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .modifier(AdaptiveFont(size: 10, weight: .semibold))
                            .foregroundStyle(SpeedometerStyle.accent)
                    }
                }
            }
            .padding(7)
            .frame(maxWidth: .infinity)
            .background(isSelected ? SpeedometerStyle.accent.opacity(0.1) : SpeedometerStyle.foreground.opacity(0.02), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? SpeedometerStyle.accent.opacity(0.72) : SpeedometerStyle.foreground.opacity(0.08), lineWidth: isSelected ? 1.2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.title) speedometer dial")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func dialPreview(_ style: SpeedometerDialStyle) -> some View {
        switch style {
        case .classic, .minimal, .sport:
            classicDialPreview(style)
        case .analog:
            analogDialPreview
        case .segmentedLED:
            segmentedDialPreview
        case .digitalHUD:
            digitalDialPreview
        case .twinRing:
            twinRingDialPreview
        }
    }

    private func classicDialPreview(_ style: SpeedometerDialStyle) -> some View {
        ZStack {
            GaugeArc(progress: 1)
                .stroke(SpeedometerStyle.foreground.opacity(0.14), style: StrokeStyle(lineWidth: style.trackWidth * 0.45, lineCap: .round))
                .frame(width: 60, height: 45)
                .offset(y: 5)
            if style == .sport {
                GaugeArc(progress: 1)
                    .trim(from: 0.84, to: 1)
                    .stroke(SpeedometerStyle.warning.opacity(0.72), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 60, height: 45)
                    .offset(y: 5)
            }
            if style.showsTicks {
                GaugeTicks(tickCount: style.tickCount, majorTickInterval: style.majorTickInterval)
                    .stroke(SpeedometerStyle.secondary.opacity(0.72), style: StrokeStyle(lineWidth: 0.75, lineCap: .round))
                    .frame(width: 60, height: 45)
                    .offset(y: 5)
            }
            GaugeArc(progress: gaugePreviewProgress)
                .stroke(SpeedometerStyle.accent, style: StrokeStyle(lineWidth: style.trackWidth * 0.45, lineCap: .round))
                .frame(width: 60, height: 45)
                .offset(y: 5)
            Text(String(format: "%.0f", displayedSpeed))
                .modifier(AdaptiveFont(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(SpeedometerStyle.foreground)
                .offset(y: 5)
        }
    }

    private var analogDialPreview: some View {
        ZStack {
            GaugeArc(progress: 1)
                .stroke(SpeedometerStyle.foreground.opacity(0.14), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            GaugeTicks(tickCount: 32, majorTickInterval: 8)
                .stroke(SpeedometerStyle.secondary.opacity(0.75), style: StrokeStyle(lineWidth: 0.65, lineCap: .round))
            GaugeNeedle(progress: gaugePreviewProgress)
                .stroke(SpeedometerStyle.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            Circle()
                .fill(SpeedometerStyle.accent)
                .frame(width: 4, height: 4)
            Text(String(format: "%.0f", displayedSpeed))
                .modifier(AdaptiveFont(size: 8, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(SpeedometerStyle.foreground)
                .offset(y: 5)
        }
        .frame(width: 60, height: 45)
        .offset(y: 5)
    }

    private var segmentedDialPreview: some View {
        ZStack {
            SegmentedGaugeArc(
                progress: gaugePreviewProgress,
                activeColor: SpeedometerStyle.accent,
                inactiveColor: SpeedometerStyle.foreground.opacity(0.14),
                segmentCount: 24,
                radiusFraction: 0.43,
                lineWidth: 3
            )
            Text(String(format: "%.0f", displayedSpeed))
                .modifier(AdaptiveFont(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(SpeedometerStyle.foreground)
                .offset(y: 5)
        }
        .frame(width: 60, height: 45)
        .offset(y: 5)
    }

    private var digitalDialPreview: some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(String(format: "%.0f", displayedSpeed))
                    .modifier(AdaptiveFont(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                Text(unit)
                    .modifier(AdaptiveFont(size: 5, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
            }
            .foregroundStyle(SpeedometerStyle.foreground)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(SpeedometerStyle.foreground.opacity(0.16))
                    Capsule()
                        .fill(SpeedometerStyle.accent)
                        .frame(width: geometry.size.width * CGFloat(gaugePreviewProgress))
                }
            }
            .frame(height: 3)

            HStack {
                Text("0")
                Spacer()
                Text("\(Int(rangeMaximum))")
            }
            .modifier(AdaptiveFont(size: 5, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(SpeedometerStyle.secondary)
        }
        .frame(width: 60, height: 40)
    }

    private var twinRingDialPreview: some View {
        ZStack {
            GaugeArc(progress: 1, radiusFraction: 0.43)
                .stroke(SpeedometerStyle.foreground.opacity(0.13), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            GaugeArc(progress: gaugePreviewProgress, radiusFraction: 0.43)
                .stroke(SpeedometerStyle.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            GaugeArc(progress: 1, radiusFraction: 0.30)
                .stroke(SpeedometerStyle.foreground.opacity(0.10), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            GaugeArc(progress: gaugePreviewProgress, radiusFraction: 0.30)
                .stroke(SpeedometerStyle.mint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            Text(String(format: "%.0f", displayedSpeed))
                .modifier(AdaptiveFont(size: 9, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(SpeedometerStyle.foreground)
                .offset(y: 5)
        }
        .frame(width: 60, height: 45)
        .offset(y: 5)
    }

    private func pageHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .modifier(AdaptiveFont(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(SpeedometerStyle.foreground)
            Text(subtitle)
                .modifier(AdaptiveFont(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 5)
        .padding(.bottom, 3)
    }

    private var unitSetting: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "speedometer")
                    .modifier(AdaptiveFont(size: 15, weight: .semibold))
                    .foregroundStyle(SpeedometerStyle.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Speed unit")
                        .modifier(AdaptiveFont(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                    Text("Applies to speed, range and distance")
                        .modifier(AdaptiveFont(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                }
                Spacer()
            }

            Picker("Speed unit", selection: $usesMiles) {
                Text("km/h").tag(false)
                Text("mph").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Speed unit")
        }
        .padding(15)
        .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 21))
    }

    private var speedWarningSetting: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $overspeedWarningEnabled) {
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge.fill")
                        .modifier(AdaptiveFont(size: 15, weight: .semibold))
                        .foregroundStyle(SpeedometerStyle.warning)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Speed warning")
                            .modifier(AdaptiveFont(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(SpeedometerStyle.foreground)
                        Text("Vibrate and highlight above the limit")
                            .modifier(AdaptiveFont(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(SpeedometerStyle.secondary)
                    }
                }
            }
            .tint(SpeedometerStyle.warning)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Warning threshold")
                            .modifier(AdaptiveFont(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(SpeedometerStyle.secondary)
                        thresholdValue
                    }
                } else {
                    HStack {
                        Text("Warning threshold")
                            .modifier(AdaptiveFont(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(SpeedometerStyle.secondary)
                        Spacer()
                        thresholdValue
                    }
                }
            }

            Slider(value: Binding(
                get: { displayedWarningThreshold },
                set: { overspeedThresholdKmh = usesMiles ? $0 / 0.621371 : $0 }
            ), in: warningThresholdRange, step: usesMiles ? 5.0 * 0.621371 : 5.0)
            .tint(SpeedometerStyle.warning)
            .accessibilityLabel("Overspeed warning threshold in \(unit)")

            HStack {
                Text(usesMiles ? "12 mph" : "20 km/h")
                Spacer()
                Text(usesMiles ? "149 mph" : "240 km/h")
            }
            .modifier(AdaptiveFont(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(SpeedometerStyle.secondary.opacity(0.8))
        }
        .padding(15)
        .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 21))
    }

    private var thresholdValue: some View {
        Text("\(Int(displayedWarningThreshold.rounded())) \(unit)")
            .modifier(AdaptiveFont(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(SpeedometerStyle.warning)
            .contentTransition(.numericText())
            .fixedSize(horizontal: false, vertical: true)
    }

    private var gpsStatusSetting: some View {
        Toggle(isOn: $showsGPSStatus) {
            HStack(spacing: 10) {
                Image(systemName: "location.circle")
                    .modifier(AdaptiveFont(size: 16, weight: .semibold))
                    .foregroundStyle(SpeedometerStyle.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("GPS signal")
                        .modifier(AdaptiveFont(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                    Text("Show signal status on Speed and Test")
                        .modifier(AdaptiveFont(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                }
            }
        }
        .tint(SpeedometerStyle.accent)
        .padding(15)
        .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 21))
        .accessibilityLabel("Show GPS signal status")
    }

    private var gpsStatus: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(model.hasGPSFix ? SpeedometerStyle.mint.opacity(0.16) : SpeedometerStyle.foreground.opacity(0.07))
                    .frame(width: 34, height: 34)
                Image(systemName: model.hasGPSFix ? "location.fill" : "location")
                    .modifier(AdaptiveFont(size: 14, weight: .semibold))
                    .foregroundStyle(model.hasGPSFix ? SpeedometerStyle.mint : SpeedometerStyle.secondary)
                    .symbolEffect(.pulse, options: .repeating, isActive: model.isSessionActive && !model.hasGPSFix && !reduceMotion)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(model.gpsStatusTitle)
                    .modifier(AdaptiveFont(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(SpeedometerStyle.foreground)
                Text(model.gpsStatusDetail)
                    .modifier(AdaptiveFont(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 6)

            Circle()
                .fill(model.hasGPSFix ? SpeedometerStyle.mint : Color.orange.opacity(0.86))
                .frame(width: 7, height: 7)
                .shadow(color: (model.hasGPSFix ? SpeedometerStyle.mint : Color.orange).opacity(0.55), radius: 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.hasGPSFix)
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.authorizationStatus)
    }

    private var dialRangeHeading: some View {
        Text("DIAL RANGE")
            .modifier(AdaptiveFont(size: 10, weight: .bold, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(SpeedometerStyle.secondary)
    }

    private var dialRangeValue: some View {
        Text("0–\(Int(rangeMaximum)) \(unit)")
            .modifier(AdaptiveFont(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(SpeedometerStyle.accent)
            .contentTransition(.numericText())
            .fixedSize(horizontal: false, vertical: true)
    }

    private var rangePicker: some View {
        VStack(alignment: .leading, spacing: 11) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        dialRangeHeading
                        dialRangeValue
                    }
                } else {
                    HStack {
                        dialRangeHeading
                        Spacer()
                        dialRangeValue
                    }
                }
            }

            if dynamicTypeSize.isAccessibilitySize {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    rangeButton(20)
                    rangeButton(50)
                    rangeButton(100)
                    customRangeButton
                }
            } else {
                HStack(spacing: 8) {
                    rangeButton(20)
                    rangeButton(50)
                    rangeButton(100)
                    customRangeButton
                }
            }

            if selectedRange == -1 {
                VStack(spacing: 3) {
                    Slider(value: Binding(
                        get: { Double(customRange) },
                        set: { customRange = Int(($0 / 5).rounded()) * 5 }
                    ), in: 20...240, step: 5)
                    .tint(SpeedometerStyle.accent)
                    .accessibilityLabel("Custom dial maximum")
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("DRAG TO SET MAXIMUM")
                                    .tracking(1.1)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                HStack {
                                    Text("20")
                                    Spacer()
                                    Text("240 \(unit)")
                                }
                            }
                        } else {
                            HStack {
                                Text("20")
                                Spacer()
                                Text("DRAG TO SET MAXIMUM")
                                    .tracking(1.1)
                                Spacer()
                                Text("240 \(unit)")
                            }
                        }
                    }
                    .modifier(AdaptiveFont(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary.opacity(0.8))
                }
                .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .top)), reduceMotion: reduceMotion))
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 21))
    }

    private var customRangeButton: some View {
        Button {
            withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) { selectedRange = -1 }
        } label: {
            Text("Custom")
                .modifier(AdaptiveFont(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(selectedRange == -1 ? SpeedometerStyle.foreground : SpeedometerStyle.secondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .glassEffect(.regular.tint(selectedRange == -1 ? SpeedometerStyle.accent.opacity(0.28) : .clear).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private func rangeButton(_ value: Int) -> some View {
        let isSelected = selectedRange == value
        return Button {
            withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) { selectedRange = value }
        } label: {
            Text("0–\(value)")
                .modifier(AdaptiveFont(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(isSelected ? SpeedometerStyle.foreground : SpeedometerStyle.secondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .glassEffect(.regular.tint(isSelected ? SpeedometerStyle.accent.opacity(0.28) : .clear).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set dial range from zero to \(value) \(unit)")
    }

}

struct SpeedometerGauge: View {
    @ObservedObject private var appearance = AppAppearance.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let speed: Double
    let maximum: Double
    let dialStyle: SpeedometerDialStyle
    let displayScale: DashboardDisplayScale
    let unit: String
    let isOverspeed: Bool

    private var progress: Double {
        guard maximum > 0 else { return 0 }
        return min(max(speed / maximum, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: diameter / 2)
            let radius = diameter * 0.43
            let gaugeColor = isOverspeed ? SpeedometerStyle.warning : SpeedometerStyle.accent

            let digitalReadoutSize = min(
                72 * displayScale.readoutMultiplier * dynamicTypeSize.veluraScaleFactor,
                max(44, proxy.size.width * 0.3)
            )
            let digitalUnitSize = min(
                15 * displayScale.readoutMultiplier * dynamicTypeSize.veluraScaleFactor,
                max(12, proxy.size.width * 0.1)
            )
            let dialReadoutSize = min(
                76 * displayScale.readoutMultiplier * dynamicTypeSize.veluraScaleFactor,
                max(44, diameter * 0.44)
            )
            let dialUnitSize = min(
                15 * displayScale.readoutMultiplier * dynamicTypeSize.veluraScaleFactor,
                max(12, diameter * 0.105)
            )
            let dialLabelSize = min(
                12 * dynamicTypeSize.veluraScaleFactor,
                max(10, diameter * 0.07)
            )

            ZStack {
                if dialStyle == .digitalHUD {
                    digitalHUD(gaugeColor: gaugeColor, readoutSize: digitalReadoutSize, unitSize: digitalUnitSize)
                        .frame(width: min(proxy.size.width * 0.94, 420))
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                } else {
                    dialFace(
                        diameter: diameter,
                        center: center,
                        radius: radius,
                        gaugeColor: gaugeColor,
                        readoutSize: dialReadoutSize,
                        unitSize: dialUnitSize,
                        labelSize: dialLabelSize
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Current speed")
            .accessibilityValue("\(Int(speed.rounded())) \(unit)")
            .accessibilityHint(isOverspeed ? "Speed warning active" : "Dial range zero to \(Int(maximum)) \(unit)")
        }
    }

    @ViewBuilder
    private func dialFace(
        diameter: CGFloat,
        center: CGPoint,
        radius: CGFloat,
        gaugeColor: Color,
        readoutSize: CGFloat,
        unitSize: CGFloat,
        labelSize: CGFloat
    ) -> some View {
        ZStack {
            if dialStyle == .twinRing {
                GaugeArc(progress: 1, radiusFraction: 0.43)
                    .stroke(SpeedometerStyle.foreground.opacity(0.10), style: StrokeStyle(lineWidth: dialStyle.trackWidth, lineCap: .round))
                    .frame(width: diameter, height: diameter)
                    .position(center)
                GaugeArc(progress: progress, radiusFraction: 0.43)
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: dialStyle.trackWidth, lineCap: .round))
                    .shadow(color: gaugeColor.opacity(0.38), radius: 8)
                    .frame(width: diameter, height: diameter)
                    .position(center)
                    .animation(VeluraMotion.animation(VeluraMotion.gauge, reduceMotion: reduceMotion), value: progress)

                let innerColor = isOverspeed ? SpeedometerStyle.warning : SpeedometerStyle.mint
                GaugeArc(progress: 1, radiusFraction: 0.31)
                    .stroke(SpeedometerStyle.foreground.opacity(0.08), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: diameter, height: diameter)
                    .position(center)
                GaugeArc(progress: progress, radiusFraction: 0.31)
                    .stroke(innerColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .shadow(color: innerColor.opacity(0.35), radius: 6)
                    .frame(width: diameter, height: diameter)
                    .position(center)
                    .animation(VeluraMotion.animation(VeluraMotion.gauge, reduceMotion: reduceMotion), value: progress)
                    .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: isOverspeed)
            } else if dialStyle == .segmentedLED {
                SegmentedGaugeArc(
                    progress: progress,
                    activeColor: gaugeColor,
                    inactiveColor: SpeedometerStyle.foreground.opacity(0.15),
                    segmentCount: 48,
                    radiusFraction: 0.43,
                    lineWidth: dialStyle.trackWidth
                )
                .frame(width: diameter, height: diameter)
                .position(center)
                .animation(VeluraMotion.animation(VeluraMotion.gauge, reduceMotion: reduceMotion), value: progress)
            } else {
                if dialStyle == .sport {
                    GaugeArc(progress: 1)
                        .trim(from: 0.84, to: 1)
                        .stroke(SpeedometerStyle.warning.opacity(0.72), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: diameter, height: diameter)
                        .position(center)
                }

                GaugeArc(progress: 1)
                    .stroke(SpeedometerStyle.foreground.opacity(0.10), style: StrokeStyle(lineWidth: dialStyle.trackWidth, lineCap: .round))
                    .frame(width: diameter, height: diameter)
                    .position(center)

                if dialStyle.showsTicks {
                    GaugeTicks(tickCount: dialStyle.tickCount, majorTickInterval: dialStyle.majorTickInterval)
                        .stroke(SpeedometerStyle.foreground.opacity(dialStyle == .sport ? 0.72 : 0.55), style: StrokeStyle(lineWidth: dialStyle == .sport ? 1.4 : 1.25, lineCap: .round))
                        .frame(width: diameter, height: diameter)
                        .position(center)
                }

                if dialStyle == .analog {
                    GaugeNeedle(progress: progress)
                        .stroke(gaugeColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .shadow(color: gaugeColor.opacity(0.35), radius: 5)
                        .frame(width: diameter, height: diameter)
                        .position(center)
                        .animation(VeluraMotion.animation(VeluraMotion.gauge, reduceMotion: reduceMotion), value: progress)
                    Circle()
                        .fill(gaugeColor)
                        .frame(width: 14, height: 14)
                        .overlay {
                            Circle().stroke(SpeedometerStyle.background, lineWidth: 3)
                        }
                        .position(center)
                } else {
                    GaugeArc(progress: progress)
                        .stroke(gaugeColor, style: StrokeStyle(lineWidth: dialStyle.trackWidth, lineCap: .round))
                        .shadow(color: gaugeColor.opacity(0.42), radius: 10)
                        .frame(width: diameter, height: diameter)
                        .position(center)
                        .animation(VeluraMotion.animation(VeluraMotion.gauge, reduceMotion: reduceMotion), value: progress)
                        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: isOverspeed)

                    let indicatorAngle = (150 + 240 * progress) * .pi / 180
                    Circle()
                        .fill(gaugeColor)
                        .frame(width: dialStyle == .sport ? 12 : 10, height: dialStyle == .sport ? 12 : 10)
                        .shadow(color: gaugeColor.opacity(0.75), radius: 8)
                        .position(x: center.x + cos(indicatorAngle) * radius, y: center.y + sin(indicatorAngle) * radius)
                        .animation(VeluraMotion.animation(VeluraMotion.gauge, reduceMotion: reduceMotion), value: progress)
                }
            }

            ForEach(0..<dialStyle.labelCount, id: \.self) { index in
                let fraction = Double(index) / Double(dialStyle.labelCount - 1)
                let angle = (150 + 240 * fraction) * .pi / 180
                let labelRadius = radius * 0.77
                Text(index == dialStyle.labelCount - 1 ? "\(Int(maximum))" : "\(Int(maximum * fraction))")
                    .font(.system(size: labelSize, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(SpeedometerStyle.secondary)
                    .position(x: center.x + cos(angle) * labelRadius, y: center.y + sin(angle) * labelRadius)
            }

            VStack(spacing: 1) {
                Text(String(format: "%.0f", speed))
                    .font(.system(size: readoutSize, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(isOverspeed ? SpeedometerStyle.warning : SpeedometerStyle.foreground)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.68)
                    .lineLimit(1)
                Text(unit)
                    .font(.system(size: unitSize, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
            }
            .position(x: center.x, y: center.y + 2)
            .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: speed)
            .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: isOverspeed)
        }
    }

    private func digitalHUD(gaugeColor: Color, readoutSize: CGFloat, unitSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("LIVE SPEED")
                    .modifier(AdaptiveFont(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(SpeedometerStyle.secondary)
                Spacer()
                Image(systemName: "waveform.path")
                    .modifier(AdaptiveFont(size: 13, weight: .semibold))
                    .foregroundStyle(gaugeColor)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.0f", speed))
                    .font(.system(size: readoutSize, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(isOverspeed ? SpeedometerStyle.warning : SpeedometerStyle.foreground)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.68)
                    .lineLimit(1)
                Text(unit)
                    .font(.system(size: unitSize, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
            }

            HStack(spacing: 10) {
                Text("0")
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(SpeedometerStyle.foreground.opacity(0.14))
                        Capsule()
                            .fill(gaugeColor)
                            .frame(width: geometry.size.width * CGFloat(progress))
                    }
                }
                .frame(height: 8)
                Text("\(Int(maximum))")
            }
            .modifier(AdaptiveFont(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(SpeedometerStyle.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(SpeedometerStyle.foreground.opacity(0.035), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(gaugeColor.opacity(0.3), lineWidth: 1)
        }
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: speed)
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: isOverspeed)
    }
}

private struct GaugeArc: Shape {
    var progress: Double
    var radiusFraction: CGFloat = 0.43

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * radiusFraction
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

private struct GaugeNeedle: Shape {
    let progress: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let angle = (150 + 240 * min(max(progress, 0), 1)) * .pi / 180
        let radius = min(rect.width, rect.height) * 0.34
        let tip = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        var path = Path()
        path.move(to: center)
        path.addLine(to: tip)
        return path
    }
}

private struct SegmentedGaugeArc: View {
    let progress: Double
    let activeColor: Color
    let inactiveColor: Color
    let segmentCount: Int
    let radiusFraction: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * radiusFraction
            let segmentStep = 240.0 / Double(segmentCount)
            let segmentSweep = segmentStep * 0.68

            for index in 0..<segmentCount {
                let start = 150 + segmentStep * Double(index)
                var segment = Path()
                segment.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .degrees(start),
                    endAngle: .degrees(start + segmentSweep),
                    clockwise: false
                )
                let color = Double(index) / Double(segmentCount) < progress ? activeColor : inactiveColor
                context.stroke(segment, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct GaugeTicks: Shape {
    let tickCount: Int
    let majorTickInterval: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.43
        let minorTickInterval = max(1, majorTickInterval / 2)
        var path = Path()
        for index in 0...tickCount {
            let angle = (150 + 240 * Double(index) / Double(tickCount)) * .pi / 180
            let tickLength: CGFloat
            if index.isMultiple(of: majorTickInterval) {
                tickLength = tickCount > 40 ? 17 : 15
            } else if index.isMultiple(of: minorTickInterval) {
                tickLength = 10
            } else {
                tickLength = 5.5
            }
            let outer = radius
            let inner = radius - tickLength
            path.move(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
            path.addLine(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
        }
        return path
    }
}

#Preview {
    ContentView()
}
