import SwiftUI

struct AccelerationTestView: View {
    @ObservedObject var model: SpeedometerModel
    @ObservedObject private var appearance = AppAppearance.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onBack: () -> Void

    private var target: Int { Int(model.accelerationTargetKmh.rounded()) }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 760

            ZStack {
                SpeedometerStyle.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: compact ? 14 : 18) {
                        header
                        targetPicker
                        if model.accelerationPreset == -1 {
                            customTargetControl
                                .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .top)), reduceMotion: reduceMotion))
                        }
                        resultCard
                        bestTimeCard
                        actionButtons
                        if !model.accelerationAttempts.isEmpty {
                            attemptHistory
                                .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .bottom)), reduceMotion: reduceMotion))
                        }
                    }
                    .padding(.horizontal, geometry.size.width < 380 ? 18 : 22)
                    .padding(.top, compact ? 4 : 10)
                    .padding(.bottom, 22)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                    .animation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion), value: model.accelerationPreset)
                    .animation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion), value: model.accelerationAttempts.map(\.id))
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(appearance.theme.colorScheme)
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 7) {
                Text("Acceleration test")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.foreground)
                Text("Measure your launch")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
            }

            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SpeedometerStyle.foreground)
                        .frame(width: 44, height: 44)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to speedometer")
                Spacer()
            }
        }
        .frame(height: 84)
        .accessibilityElement(children: .contain)
    }

    private var targetPicker: some View {
        HStack(spacing: 4) {
            ForEach([20, 50, 100], id: \.self) { preset in
                targetButton(title: "0–\(preset)", isSelected: model.accelerationPreset == preset) {
                    withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                        model.selectAccelerationPreset(preset)
                    }
                }
                .accessibilityLabel("Acceleration target zero to \(preset) kilometres per hour")
            }

            targetButton(title: "Custom", isSelected: model.accelerationPreset == -1) {
                withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                    model.selectCustomAccelerationTarget(Double(model.customAccelerationTargetKmh))
                }
            }
            .accessibilityLabel("Custom acceleration target")
        }
        .padding(5)
        .frame(height: 58)
        .background(SpeedometerStyle.foreground.opacity(0.035), in: Capsule())
        .glassEffect(.regular, in: .capsule)
        .overlay {
            Capsule().stroke(SpeedometerStyle.foreground.opacity(0.11), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Acceleration target")
        .animation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion), value: model.accelerationPreset)
    }

    private func targetButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(isSelected ? SpeedometerStyle.accentForeground : SpeedometerStyle.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(SpeedometerStyle.accent)
                            .overlay { Capsule().stroke(SpeedometerStyle.foreground.opacity(0.24), lineWidth: 1) }
                            .shadow(color: SpeedometerStyle.accent.opacity(0.3), radius: 10, y: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var customTargetControl: some View {
        VStack(spacing: 5) {
            HStack {
                Text("CUSTOM TARGET")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(SpeedometerStyle.secondary)
                Spacer()
                Text("\(target) km/h")
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(SpeedometerStyle.accent)
                    .contentTransition(.numericText())
            }

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
            .foregroundStyle(SpeedometerStyle.secondary.opacity(0.82))
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(SpeedometerStyle.foreground.opacity(0.035), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 19))
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(SpeedometerStyle.foreground.opacity(0.09), lineWidth: 1)
        }
        .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .top)), reduceMotion: reduceMotion))
    }

    private var resultCard: some View {
        VStack(spacing: 17) {
            Text(stateTitle)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .tracking(2.2)
                .foregroundStyle(model.accelerationState == .completed && model.isNewAccelerationBest ? SpeedometerStyle.mint : SpeedometerStyle.secondary)
                .contentTransition(.opacity)

            TimelineView(.animation(minimumInterval: 0.05, paused: model.accelerationState != .timing)) { context in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%.2f", model.accelerationElapsed(at: context.date)))
                        .font(.system(size: 75, weight: .light, design: .rounded).monospacedDigit())
                        .foregroundStyle(model.accelerationState == .completed ? SpeedometerStyle.accent : SpeedometerStyle.foreground)
                        .contentTransition(.numericText())
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                    Text("s")
                        .font(.system(size: 43, weight: .medium, design: .rounded))
                        .foregroundStyle(model.accelerationState == .completed ? SpeedometerStyle.accent : SpeedometerStyle.foreground)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Acceleration time")
                .accessibilityValue("\(String(format: "%.2f", model.accelerationElapsed(at: context.date))) seconds")
                .transaction { transaction in
                    transaction.animation = VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion)
                }
            }

            Text(stateDetail)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 27)
        .frame(maxWidth: .infinity, minHeight: 226)
        .background(SpeedometerStyle.foreground.opacity(0.035), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(SpeedometerStyle.foreground.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.accelerationState)
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.isNewAccelerationBest)
    }

    private var bestTimeCard: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 8) {
                Text("BEST")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(SpeedometerStyle.secondary)
                Text(model.bestAccelerationTime.map(accelerationTimeText) ?? "—")
                    .font(.system(size: 27, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(model.isNewAccelerationBest ? SpeedometerStyle.mint : SpeedometerStyle.foreground)
                    .contentTransition(.numericText())
            }
            Spacer()
            if model.isNewAccelerationBest {
                Label("NEW BEST", systemImage: "sparkle")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(SpeedometerStyle.mint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(SpeedometerStyle.mint.opacity(0.1), in: Capsule())
                    .transition(VeluraMotion.transition(.opacity.combined(with: .scale(scale: 0.96)), reduceMotion: reduceMotion))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 93, alignment: .leading)
        .background(SpeedometerStyle.foreground.opacity(0.035), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(SpeedometerStyle.foreground.opacity(0.1), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.isNewAccelerationBest)
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.bestAccelerationTime)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                    model.startAccelerationTest()
                }
            } label: {
                Text(primaryActionTitle)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.accentForeground)
                    .contentTransition(.opacity)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(SpeedometerStyle.accent, in: Capsule())
                    .glassEffect(.regular.tint(SpeedometerStyle.accent.opacity(0.25)).interactive(), in: .capsule)
                    .overlay { Capsule().stroke(SpeedometerStyle.foreground.opacity(0.32), lineWidth: 1) }
                    .shadow(color: SpeedometerStyle.accent.opacity(0.34), radius: 15, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(model.accelerationState == .waitingForMovement || model.accelerationState == .timing)
            .accessibilityHint("Arms GPS timing from a standstill, or starts another run")

            Button {
                withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                    model.resetAccelerationTest()
                }
            } label: {
                Text("Reset")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reset acceleration test")
        }
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.accelerationState)
    }

    private var attemptHistory: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SpeedometerStyle.accent)
                Text("RECENT RUNS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(SpeedometerStyle.secondary)
                Spacer()
                Text("\(model.accelerationAttempts.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(SpeedometerStyle.secondary)
            }

            ForEach(model.accelerationAttemptGroups) { group in
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("0–\(group.targetKmh) km/h")
                            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(SpeedometerStyle.foreground)
                        Spacer()
                        Text(group.bestTime.map(accelerationTimeText) ?? "—")
                            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(SpeedometerStyle.mint)
                    }

                    ForEach(group.attempts) { attempt in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(attempt.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(SpeedometerStyle.foreground.opacity(0.84))
                                Text(accelerationTimeText(attempt.duration))
                                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                                    .foregroundStyle(SpeedometerStyle.secondary)
                            }
                            Spacer()
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
                            .accessibilityLabel("Delete \(group.targetKmh) kilometre per hour attempt")
                        }
                    }
                }
                if group.id != model.accelerationAttemptGroups.last?.id {
                    Rectangle()
                        .fill(SpeedometerStyle.foreground.opacity(0.1))
                        .frame(height: 1)
                }
            }
        }
        .padding(16)
        .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 21))
    }

    private var stateTitle: String {
        switch model.accelerationState {
        case .ready: return "READY"
        case .waitingForMovement:
            if !model.isSessionActive || !model.hasGPSFix { return "GPS STANDBY" }
            return model.canBeginAccelerationRun ? "ARMED" : "WAIT FOR STOP"
        case .timing: return "TIMING"
        case .completed: return model.isNewAccelerationBest ? "NEW BEST" : "COMPLETE"
        }
    }

    private var stateDetail: String {
        switch model.accelerationState {
        case .ready:
            return "Start from a standstill to begin timing"
        case .waitingForMovement:
            if !model.isSessionActive || !model.hasGPSFix {
                return model.gpsStatusDetail == "Allow location access in Settings"
                    ? "Allow location access to measure your launch"
                    : "Waiting for a clear GPS fix to arm the timer"
            } else if model.canBeginAccelerationRun {
                return "Accelerate to \(target) km/h to start timing"
            } else {
                return "Come to a full stop to arm the timer"
            }
        case .timing:
            return "Accelerate to \(target) km/h"
        case .completed:
            return model.isNewAccelerationBest ? "Target reached · new best saved" : "Target reached · run saved"
        }
    }

    private var primaryActionTitle: String {
        switch model.accelerationState {
        case .ready: return "Arm test"
        case .waitingForMovement: return "Waiting for launch"
        case .timing: return "Timing run"
        case .completed: return "Try again"
        }
    }

    private func accelerationTimeText(_ time: TimeInterval) -> String {
        String(format: "%.2f s", time)
    }
}
