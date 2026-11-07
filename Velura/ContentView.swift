import SwiftUI
import UIKit

enum SpeedometerStyle {
    static var background: Color { AppAppearance.shared.theme.background }
    static var foreground: Color { AppAppearance.shared.theme.foreground }
    static var secondary: Color { AppAppearance.shared.theme.secondary }
    static var accent: Color { AppAppearance.shared.theme.accent }
    static var accentForeground: Color { AppAppearance.shared.theme.accentForeground }
    static var mint: Color { AppAppearance.shared.theme.mint }
    static var warning: Color { AppAppearance.shared.theme.warning }
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

    private var unit: String { usesMiles ? "mph" : "km/h" }
    private var spokenUnit: String { usesMiles ? "miles per hour" : "kilometres per hour" }
    private var unitConversion: Double { usesMiles ? 0.621371 : 1 }
    private var displayedSpeed: Double { usesMiles ? model.speedKmh * 0.621371 : model.speedKmh }
    private var displayedAccelerationTarget: Int { Int((model.accelerationTargetKmh * unitConversion).rounded()) }
    private func displayedSpeed(for speedKmh: Double) -> Double { speedKmh * unitConversion }
    private func displayedAccelerationTarget(for targetKmh: Int) -> Int { Int((Double(targetKmh) * unitConversion).rounded()) }
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
        .preferredColorScheme(appearance.theme.colorScheme)
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

    private var speedWarningBanner: some View {
        HStack(spacing: 11) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SpeedometerStyle.warning)
                .symbolEffect(.pulse, options: .repeating, isActive: model.isOverspeedWarningActive && !reduceMotion)

            VStack(alignment: .leading, spacing: 3) {
                Text("SPEED WARNING")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(SpeedometerStyle.warning)
                Text("Limit \(Int(displayedWarningThreshold.rounded())) \(unit)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.foreground.opacity(0.86))
            }

            Spacer(minLength: 8)

            Text("\(Int(displayedSpeed.rounded())) \(unit)")
                .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(SpeedometerStyle.foreground)
                .contentTransition(.numericText())
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
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 28)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var dashboardDisplayScaleSetting: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SpeedometerStyle.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dashboard display")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                    Text("Scale the gauge and speed readout")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                }
            }

            Picker("Dashboard scale", selection: $dashboardDisplayScaleRawValue) {
                ForEach(DashboardDisplayScale.allCases) { scale in
                    Text(scale.title).tag(scale.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Dashboard display scale")

            Text("Controls and trip metrics stay full size.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SpeedometerStyle.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Appearance")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                    Text("Choose a theme and dial style")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("APP THEME")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(SpeedometerStyle.secondary)
                HStack(spacing: 8) {
                    ForEach(AppearanceTheme.allCases) { theme in
                        themeOption(theme)
                    }
                }
            }

            if appearance.theme == .custom {
                customThemeControls
                    .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .top)), reduceMotion: reduceMotion))
            }

            Rectangle()
                .fill(SpeedometerStyle.foreground.opacity(0.1))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 9) {
                Text("SPEEDOMETER DIAL")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(SpeedometerStyle.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
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

    private var customThemeControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Custom colors")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                    Text("Tune your background, accent and positive status color")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                }
                Spacer(minLength: 0)
            }

            customColorPicker("Background", detail: "Screen and card surfaces", selection: $appearance.customBackgroundColor)
            customColorPicker("Accent", detail: "Controls and speed highlights", selection: $appearance.customAccentColor)
            customColorPicker("Positive status", detail: "GPS lock and successful runs", selection: $appearance.customPositiveColor)

            customThemePreview

            Button {
                withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                    appearance.resetCustomColors()
                }
            } label: {
                Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(SpeedometerStyle.foreground.opacity(0.035), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(SpeedometerStyle.foreground.opacity(0.1), lineWidth: 1)
        }
    }

    private func customColorPicker(_ title: String, detail: String, selection: Binding<Color>) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.foreground)
                Text(detail)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
            }
            Spacer(minLength: 4)
            ColorPicker(title, selection: selection, supportsOpacity: false)
                .labelsHidden()
                .tint(SpeedometerStyle.accent)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(SpeedometerStyle.foreground.opacity(0.035), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var customThemePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "speedometer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SpeedometerStyle.accent)
                Text("VELURA")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(SpeedometerStyle.foreground)
                Spacer()
                Label("GPS ready", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.mint)
            }

            HStack(alignment: .center) {
                Text("\(Int(displayedSpeed(for: 72).rounded())) \(unit)")
                    .font(.system(size: 25, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(SpeedometerStyle.foreground)
                Spacer()
                Button {} label: {
                    Text("Start drive")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.accentForeground)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(SpeedometerStyle.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(true)
            }

            Label("Speed warning", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.warning)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SpeedometerStyle.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(SpeedometerStyle.foreground.opacity(0.16), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live preview of custom colors, with fixed red speed warnings")
    }

    private func themeOption(_ theme: AppearanceTheme) -> some View {
        let isSelected = appearance.theme == theme
        return Button {
            withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) { appearance.theme = theme }
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                themePreview(theme)
                    .frame(height: 58)
                HStack(spacing: 3) {
                    Text(theme.title)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
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
                    .font(.system(size: 14, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(theme.foreground)
                Text(unit)
                    .font(.system(size: 6, weight: .medium, design: .rounded))
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
                    .frame(height: 47)
                HStack(spacing: 3) {
                    Text(style.title)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
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
                .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
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
                .font(.system(size: 8, weight: .semibold, design: .rounded).monospacedDigit())
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
                .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
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
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                Text(unit)
                    .font(.system(size: 5, weight: .medium, design: .rounded))
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
            .font(.system(size: 5, weight: .medium, design: .rounded).monospacedDigit())
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
                .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(SpeedometerStyle.foreground)
                .offset(y: 5)
        }
        .frame(width: 60, height: 45)
        .offset(y: 5)
    }

    private func pageHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(SpeedometerStyle.foreground)
            Text(subtitle)
                .font(.system(size: 12, weight: .medium, design: .rounded))
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SpeedometerStyle.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Speed unit")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                    Text("Applies to speed, range and distance")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SpeedometerStyle.warning)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Speed warning")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(SpeedometerStyle.foreground)
                        Text("Vibrate and highlight above the limit")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(SpeedometerStyle.secondary)
                    }
                }
            }
            .tint(SpeedometerStyle.warning)

            HStack {
                Text("Warning threshold")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
                Spacer()
                Text("\(Int(displayedWarningThreshold.rounded())) \(unit)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(SpeedometerStyle.warning)
                    .contentTransition(.numericText())
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
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(SpeedometerStyle.secondary.opacity(0.8))
        }
        .padding(15)
        .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 21))
    }

    private var gpsStatusSetting: some View {
        Toggle(isOn: $showsGPSStatus) {
            HStack(spacing: 10) {
                Image(systemName: "location.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(SpeedometerStyle.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("GPS signal")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                    Text("Show signal status on Speed and Test")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(model.hasGPSFix ? SpeedometerStyle.mint : SpeedometerStyle.secondary)
                    .symbolEffect(.pulse, options: .repeating, isActive: model.isSessionActive && !model.hasGPSFix && !reduceMotion)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(model.gpsStatusTitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(SpeedometerStyle.foreground)
                Text(model.gpsStatusDetail)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
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

    private var accelerationTest: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "stopwatch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SpeedometerStyle.accent)
                Text("ACCELERATION TEST")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(SpeedometerStyle.secondary)
                Spacer()
                Text("0–\(displayedAccelerationTarget) \(unit)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(SpeedometerStyle.accent)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 7) {
                accelerationPresetButton(20)
                accelerationPresetButton(50)
                accelerationPresetButton(100)
                Button {
                    withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                        model.selectCustomAccelerationTarget(Double(model.customAccelerationTargetKmh))
                    }
                } label: {
                    Text("Custom")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(model.accelerationPreset == -1 ? SpeedometerStyle.foreground : SpeedometerStyle.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .glassEffect(.regular.tint(model.accelerationPreset == -1 ? SpeedometerStyle.accent.opacity(0.28) : .clear).interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
            }

            if model.accelerationPreset == -1 {
                VStack(spacing: 2) {
                    Slider(value: Binding(
                        get: { Double(model.customAccelerationTargetKmh) * unitConversion },
                        set: { model.selectCustomAccelerationTarget($0 / unitConversion) }
                    ), in: (20 * unitConversion)...(240 * unitConversion), step: 5 * unitConversion)
                    .tint(SpeedometerStyle.accent)
                    .accessibilityLabel("Custom acceleration target in \(spokenUnit)")
                    .accessibilityValue("\(Int((Double(model.customAccelerationTargetKmh) * unitConversion).rounded())) \(spokenUnit)")
                    HStack {
                        Text("\(Int((20 * unitConversion).rounded())) \(unit)")
                        Spacer()
                        Text("\(Int((240 * unitConversion).rounded())) \(unit)")
                    }
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary.opacity(0.8))
                }
                .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .top)), reduceMotion: reduceMotion))
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(accelerationStatusTitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                        .contentTransition(.opacity)
                    Text(accelerationStatusDetail)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 2)

                TimelineView(.animation(minimumInterval: 0.05, paused: model.accelerationState != .timing)) { context in
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(accelerationTimeText(model.accelerationElapsed(at: context.date)))
                            .font(.system(size: 21, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(model.accelerationState == .completed ? SpeedometerStyle.mint : SpeedometerStyle.foreground)
                            .contentTransition(.numericText())
                        Text(model.bestAccelerationTime.map { "BEST \(accelerationTimeText($0))" } ?? "BEST —")
                            .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                            .tracking(0.5)
                            .foregroundStyle(model.isNewAccelerationBest ? SpeedometerStyle.mint : SpeedometerStyle.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Elapsed time and best acceleration result")
            }

            Button {
                withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                    if model.accelerationState == .waitingForMovement || model.accelerationState == .timing {
                        model.resetAccelerationTest()
                    } else {
                        model.startAccelerationTest()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: accelerationButtonSymbol)
                        .font(.system(size: 11, weight: .bold))
                    Text(accelerationButtonTitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(SpeedometerStyle.foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 39)
                .glassEffect(.regular.tint(SpeedometerStyle.accent.opacity(0.2)).interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Arms a GPS acceleration run, or resets the current attempt")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 21))
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.accelerationState)
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.isNewAccelerationBest)
    }

    private var accelerationAttemptHistory: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SpeedometerStyle.accent)
                Text("RECENT ATTEMPTS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(SpeedometerStyle.secondary)
                Spacer()
                Text("\(model.accelerationAttempts.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(SpeedometerStyle.secondary)
            }

            if model.accelerationAttemptGroups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "stopwatch")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(SpeedometerStyle.accent.opacity(0.8))
                    Text("No completed runs yet")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                    Text("Your attempts and best times will be saved here by target.")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
            } else {
                ForEach(model.accelerationAttemptGroups) { group in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .center) {
                            Text("0–\(displayedAccelerationTarget(for: group.targetKmh)) \(unit)")
                                .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(SpeedometerStyle.foreground)

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text("BEST")
                                    .font(.system(size: 8, weight: .bold, design: .rounded))
                                    .tracking(0.8)
                                    .foregroundStyle(SpeedometerStyle.secondary)
                                Text(group.bestTime.map { accelerationTimeText($0) } ?? "—")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(SpeedometerStyle.mint)
                            }
                        }

                        ForEach(group.attempts) { attempt in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(attempt.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundStyle(SpeedometerStyle.foreground.opacity(0.84))
                                    Text("\(accelerationTimeText(attempt.duration)) · 0–\(displayedAccelerationTarget(for: attempt.targetKmh)) \(unit)")
                                        .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                                        .foregroundStyle(SpeedometerStyle.secondary)
                                }

                                Spacer(minLength: 4)

                                Button(role: .destructive) {
                                    model.deleteAccelerationAttempt(attempt.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(SpeedometerStyle.warning)
                                        .frame(width: 34, height: 34)
                                        .glassEffect(.regular.tint(SpeedometerStyle.warning.opacity(0.12)).interactive(), in: .circle)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Delete zero to \(displayedAccelerationTarget(for: attempt.targetKmh)) \(spokenUnit) attempt")
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    if group.id != model.accelerationAttemptGroups.last?.id {
                        Rectangle()
                            .fill(SpeedometerStyle.foreground.opacity(0.1))
                            .frame(height: 1)
                    }
                }
            }
        }
        .padding(15)
        .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 21))
    }

    private func accelerationPresetButton(_ preset: Int) -> some View {
        let isSelected = model.accelerationPreset == preset
        return Button {
            withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                model.selectAccelerationPreset(preset)
            }
        } label: {
            Text("0–\(displayedAccelerationTarget(for: preset)) \(unit)")
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(isSelected ? SpeedometerStyle.foreground : SpeedometerStyle.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .glassEffect(.regular.tint(isSelected ? SpeedometerStyle.accent.opacity(0.28) : .clear).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Acceleration test from zero to \(displayedAccelerationTarget(for: preset)) \(spokenUnit)")
    }

    private var accelerationStatusTitle: String {
        switch model.accelerationState {
        case .ready: "Ready to test"
        case .waitingForMovement: "Waiting for movement"
        case .timing: "Run in progress"
        case .completed: model.isNewAccelerationBest ? "New personal best" : "Test complete"
        }
    }

    private var accelerationStatusDetail: String {
        switch model.accelerationState {
        case .ready:
            model.isSessionActive ? "Arms at a standstill" : "Arming starts GPS if needed"
        case .waitingForMovement:
            model.canBeginAccelerationRun ? "Accelerate from a standstill" : "Come to a stop before launch"
        case .timing:
            "Accelerate to the selected target"
        case .completed:
            "Target reached · best time saved"
        }
    }

    private var accelerationButtonTitle: String {
        switch model.accelerationState {
        case .ready: "Start test"
        case .waitingForMovement, .timing: "Reset test"
        case .completed: "Retry test"
        }
    }

    private var accelerationButtonSymbol: String {
        switch model.accelerationState {
        case .ready: "play.fill"
        case .waitingForMovement, .timing: "stop.fill"
        case .completed: "arrow.counterclockwise"
        }
    }

    private func accelerationTimeText(_ time: TimeInterval) -> String {
        String(format: "%.2f s", time)
    }

    private var rangePicker: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("DIAL RANGE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(SpeedometerStyle.secondary)
                Spacer()
                Text("0–\(Int(rangeMaximum)) \(unit)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(SpeedometerStyle.accent)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 8) {
                rangeButton(20)
                rangeButton(50)
                rangeButton(100)
                Button {
                    withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) { selectedRange = -1 }
                } label: {
                    Text("Custom")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(selectedRange == -1 ? SpeedometerStyle.foreground : SpeedometerStyle.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .glassEffect(.regular.tint(selectedRange == -1 ? SpeedometerStyle.accent.opacity(0.28) : .clear).interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
            }

            if selectedRange == -1 {
                VStack(spacing: 3) {
                    Slider(value: Binding(
                        get: { Double(customRange) },
                        set: { customRange = Int(($0 / 5).rounded()) * 5 }
                    ), in: 20...240, step: 5)
                    .tint(SpeedometerStyle.accent)
                    .accessibilityLabel("Custom dial maximum")
                    HStack {
                        Text("20")
                        Spacer()
                        Text("DRAG TO SET MAXIMUM")
                            .tracking(1.1)
                        Spacer()
                        Text("240 \(unit)")
                    }
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
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

    private func rangeButton(_ value: Int) -> some View {
        let isSelected = selectedRange == value
        return Button {
            withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) { selectedRange = value }
        } label: {
            Text("0–\(value)")
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(isSelected ? SpeedometerStyle.foreground : SpeedometerStyle.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(isSelected ? SpeedometerStyle.accent.opacity(0.28) : .clear).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set dial range from zero to \(value) \(unit)")
    }

}

struct SpeedometerGauge: View {
    @ObservedObject private var appearance = AppAppearance.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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

            ZStack {
                if dialStyle == .digitalHUD {
                    digitalHUD(gaugeColor: gaugeColor)
                        .frame(width: min(proxy.size.width * 0.94, 420))
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                } else {
                    dialFace(diameter: diameter, center: center, radius: radius, gaugeColor: gaugeColor)
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
    private func dialFace(diameter: CGFloat, center: CGPoint, radius: CGFloat, gaugeColor: Color) -> some View {
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
                    .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(SpeedometerStyle.secondary)
                    .position(x: center.x + cos(angle) * labelRadius, y: center.y + sin(angle) * labelRadius)
            }

            VStack(spacing: 1) {
                Text(String(format: "%.0f", speed))
                    .font(.system(size: 76 * displayScale.readoutMultiplier, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(isOverspeed ? SpeedometerStyle.warning : SpeedometerStyle.foreground)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.68)
                    .lineLimit(1)
                Text(unit)
                    .font(.system(size: 15 * displayScale.readoutMultiplier, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
            }
            .position(x: center.x, y: center.y + 2)
            .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: speed)
            .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: isOverspeed)
        }
    }

    private func digitalHUD(gaugeColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Text("LIVE SPEED")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(SpeedometerStyle.secondary)
                Spacer()
                Image(systemName: "waveform.path")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(gaugeColor)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.0f", speed))
                    .font(.system(size: 72 * displayScale.readoutMultiplier, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(isOverspeed ? SpeedometerStyle.warning : SpeedometerStyle.foreground)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.68)
                    .lineLimit(1)
                Text(unit)
                    .font(.system(size: 15 * displayScale.readoutMultiplier, weight: .medium, design: .rounded))
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
            .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
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
