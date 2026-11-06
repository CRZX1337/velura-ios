import SwiftUI
import UIKit

enum SpeedometerStyle {
    static let background = Color(red: 0.025, green: 0.043, blue: 0.067)
    static let secondary = Color(red: 0.56, green: 0.64, blue: 0.72)
    static let accent = Color(red: 0.27, green: 0.79, blue: 0.98)
    static let mint = Color(red: 0.34, green: 0.91, blue: 0.73)
    static let warning = Color(red: 1.0, green: 0.34, blue: 0.31)
}

private enum MainTab: Hashable {
    case speedometer
    case acceleration
    case history
    case settings
}

struct ContentView: View {
    @StateObject private var model = SpeedometerModel()
    @AppStorage("speedometer.selectedRange") private var selectedRange = 50
    @AppStorage("speedometer.customRange") private var customRange = 160
    @AppStorage("speedometer.usesMiles") private var usesMiles = false
    @AppStorage("speedometer.showsGPSStatus") private var showsGPSStatus = true
    @AppStorage("speedometer.overspeed.enabled") private var overspeedWarningEnabled = false
    @AppStorage("speedometer.overspeed.thresholdKmh") private var overspeedThresholdKmh = 100.0
    @State private var showingResetConfirmation = false
    @State private var selectedTab: MainTab = .speedometer
    @Environment(\.openURL) private var openURL

    private var unit: String { usesMiles ? "mph" : "km/h" }
    private var displayedSpeed: Double { usesMiles ? model.speedKmh * 0.621371 : model.speedKmh }
    private var rangeMaximum: Double { Double(selectedRange == -1 ? customRange : selectedRange) }
    private var displayedWarningThreshold: Double { usesMiles ? overspeedThresholdKmh * 0.621371 : overspeedThresholdKmh }
    private var warningThresholdRange: ClosedRange<Double> {
        let conversion = usesMiles ? 0.621371 : 1.0
        return (20.0 * conversion)...(240.0 * conversion)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            speedometerScreen
                .tabItem { Label("Speed", systemImage: "speedometer") }
                .tag(MainTab.speedometer)

            accelerationScreen
                .tabItem { Label("Test", systemImage: "stopwatch") }
                .tag(MainTab.acceleration)

            DriveHistoryView()
                .tabItem { Label("Drives", systemImage: "clock.arrow.circlepath") }
                .tag(MainTab.history)

            settingsScreen
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                .tag(MainTab.settings)
        }
        .tint(SpeedometerStyle.accent)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .top, spacing: 0) {
            if model.isOverspeedWarningActive {
                speedWarningBanner
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: model.isOverspeedWarningActive)
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
                .symbolEffect(.pulse, options: .repeating, isActive: model.isOverspeedWarningActive)

            VStack(alignment: .leading, spacing: 3) {
                Text("SPEED WARNING")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(SpeedometerStyle.warning)
                Text("Limit \(Int(displayedWarningThreshold.rounded())) \(unit)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.86))
            }

            Spacer(minLength: 8)

            Text("\(Int(displayedSpeed.rounded())) \(unit)")
                .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
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
            usesMiles: usesMiles,
            rangeMaximum: rangeMaximum,
            showsGPSStatus: showsGPSStatus,
            onResetRequested: { showingResetConfirmation = true }
        )
        .confirmationDialog("Reset this drive?", isPresented: $showingResetConfirmation, titleVisibility: .visible) {
            Button("Reset drive", role: .destructive) {
                withAnimation(.snappy) { model.resetSession() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your top speed, distance and drive time will be cleared.")
        }
    }

    private var accelerationScreen: some View {
        ZStack {
            SpeedometerStyle.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    pageHeader(title: "Acceleration", subtitle: "Time your launch")
                    if showsGPSStatus { gpsStatus }
                    accelerationTest
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 28)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
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
                }
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 28)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func pageHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
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
                        .foregroundStyle(.white)
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
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
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
                            .foregroundStyle(.white)
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
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
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
                        .foregroundStyle(.white)
                    Text("Show signal status on Speed and Test")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                }
            }
        }
        .tint(SpeedometerStyle.accent)
        .padding(15)
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 21))
        .accessibilityLabel("Show GPS signal status")
    }

    private var gpsStatus: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(model.hasGPSFix ? SpeedometerStyle.mint.opacity(0.16) : Color.white.opacity(0.07))
                    .frame(width: 34, height: 34)
                Image(systemName: model.hasGPSFix ? "location.fill" : "location")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(model.hasGPSFix ? SpeedometerStyle.mint : SpeedometerStyle.secondary)
                    .symbolEffect(.pulse, options: .repeating, isActive: model.isSessionActive && !model.hasGPSFix)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(model.gpsStatusTitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.white)
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
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
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
                Text("0–\(Int(model.accelerationTargetKmh)) km/h")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(SpeedometerStyle.accent)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 7) {
                accelerationPresetButton(20)
                accelerationPresetButton(50)
                accelerationPresetButton(100)
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
                        model.selectCustomAccelerationTarget(Double(model.customAccelerationTargetKmh))
                    }
                } label: {
                    Text("Custom")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(model.accelerationPreset == -1 ? .white : SpeedometerStyle.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .glassEffect(.regular.tint(model.accelerationPreset == -1 ? SpeedometerStyle.accent.opacity(0.28) : .clear).interactive(), in: .capsule)
                }
                .buttonStyle(.plain)
            }

            if model.accelerationPreset == -1 {
                VStack(spacing: 2) {
                    Slider(value: Binding(
                        get: { Double(model.customAccelerationTargetKmh) },
                        set: { model.selectCustomAccelerationTarget($0) }
                    ), in: 20...240, step: 5)
                    .tint(SpeedometerStyle.accent)
                    .accessibilityLabel("Custom acceleration target in kilometres per hour")
                    HStack {
                        Text("20 km/h")
                        Spacer()
                        Text("240 km/h")
                    }
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary.opacity(0.8))
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(accelerationStatusTitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
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
                            .foregroundStyle(model.accelerationState == .completed ? SpeedometerStyle.mint : .white)
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
                withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
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
                        .symbolEffect(.bounce, value: model.accelerationState)
                    Text(accelerationButtonTitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 39)
                .glassEffect(.regular.tint(SpeedometerStyle.accent.opacity(0.2)).interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Arms a GPS acceleration run, or resets the current attempt")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 21))
    }

    private func accelerationPresetButton(_ preset: Int) -> some View {
        let isSelected = model.accelerationPreset == preset
        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.76)) {
                model.selectAccelerationPreset(preset)
            }
        } label: {
            Text("0–\(preset)")
                .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(isSelected ? .white : SpeedometerStyle.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .glassEffect(.regular.tint(isSelected ? SpeedometerStyle.accent.opacity(0.28) : .clear).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Acceleration test from zero to \(preset) kilometres per hour")
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
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { selectedRange = -1 }
                } label: {
                    Text("Custom")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(selectedRange == -1 ? .white : SpeedometerStyle.secondary)
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
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 21))
    }

    private func rangeButton(_ value: Int) -> some View {
        let isSelected = selectedRange == value
        return Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.74)) { selectedRange = value }
        } label: {
            Text("0–\(value)")
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(isSelected ? .white : SpeedometerStyle.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .glassEffect(.regular.tint(isSelected ? SpeedometerStyle.accent.opacity(0.28) : .clear).interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set dial range from zero to \(value) \(unit)")
    }

}

struct SpeedometerGauge: View {
    let speed: Double
    let maximum: Double
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
            let indicatorAngle = (150 + 240 * progress) * .pi / 180
            let gaugeColor = isOverspeed ? SpeedometerStyle.warning : SpeedometerStyle.accent

            ZStack {
                GaugeArc(progress: 1)
                    .stroke(.white.opacity(0.10), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: diameter, height: diameter)
                    .position(center)

                GaugeTicks()
                    .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
                    .frame(width: diameter, height: diameter)
                    .position(center)

                GaugeArc(progress: progress)
                    .stroke(gaugeColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .shadow(color: gaugeColor.opacity(0.42), radius: 10)
                    .frame(width: diameter, height: diameter)
                    .position(center)
                    .animation(.smooth(duration: 0.65), value: progress)
                    .animation(.snappy(duration: 0.3), value: isOverspeed)

                Circle()
                    .fill(gaugeColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: gaugeColor.opacity(0.75), radius: 8)
                    .position(x: center.x + cos(indicatorAngle) * radius, y: center.y + sin(indicatorAngle) * radius)
                    .animation(.spring(response: 0.65, dampingFraction: 0.82), value: progress)

                ForEach(0...4, id: \.self) { index in
                    let fraction = Double(index) / 4
                    let angle = (150 + 240 * fraction) * .pi / 180
                    let labelRadius = radius * 0.77
                    Text(index == 4 ? "\(Int(maximum))" : "\(Int(maximum * fraction))")
                        .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(SpeedometerStyle.secondary)
                        .position(x: center.x + cos(angle) * labelRadius, y: center.y + sin(angle) * labelRadius)
                }

                VStack(spacing: 1) {
                    Text(String(format: "%.0f", speed))
                        .font(.system(size: 76, weight: .light, design: .rounded).monospacedDigit())
                        .foregroundStyle(isOverspeed ? SpeedometerStyle.warning : .white)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.68)
                        .lineLimit(1)
                    Text(unit)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                }
                .position(x: center.x, y: center.y + 2)
                .animation(.snappy(duration: 0.35), value: speed)
                .animation(.snappy(duration: 0.3), value: isOverspeed)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Current speed")
            .accessibilityValue("\(Int(speed.rounded())) \(unit)")
            .accessibilityHint(isOverspeed ? "Speed warning active" : "Dial range zero to \(Int(maximum)) \(unit)")
        }
    }
}

private struct GaugeArc: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.43
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

private struct GaugeTicks: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.43
        var path = Path()
        for index in 0...40 {
            let angle = (150 + 240 * Double(index) / 40) * .pi / 180
            let tickLength: CGFloat
            if index.isMultiple(of: 10) {
                tickLength = 15
            } else if index.isMultiple(of: 5) {
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
