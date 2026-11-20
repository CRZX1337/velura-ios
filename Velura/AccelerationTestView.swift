import SwiftUI

struct AccelerationTestView: View {
    @ObservedObject var model: SpeedometerModel
    @ObservedObject private var appearance = AppAppearance.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var targetSelectionNamespace
    @Namespace private var actionsGlassNamespace
    @AppStorage("speedometer.usesMiles") private var usesMiles = false

    private var unitConversion: Double { usesMiles ? 0.621371 : 1 }
    private var speedUnit: String { usesMiles ? "mph" : "km/h" }
    private var spokenSpeedUnit: String { usesMiles ? "miles per hour" : "kilometres per hour" }
    private var target: Int { displayedTarget(Int(model.accelerationTargetKmh.rounded())) }

    private func displayedTarget(_ targetKmh: Int) -> Int {
        Int((Double(targetKmh) * unitConversion).rounded())
    }

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            let compact = geometry.size.height < 760 || landscape
            let stackedTargets = geometry.size.width < 390 || dynamicTypeSize.isAccessibilitySize

            ZStack {
                VeluraAmbientBackdrop(
                    intensity: model.accelerationState == .timing ? 0.55 : (model.accelerationState == .completed ? 0.32 : 0.16),
                    isWarning: model.accelerationInterruptedForGPS,
                    isActive: model.accelerationState == .timing || model.accelerationState == .waitingForMovement
                )

                ScrollView(showsIndicators: false) {
                    VStack(spacing: compact ? 14 : 18) {
                        header
                        targetPicker(isStacked: stackedTargets)
                        if model.accelerationPreset == -1 {
                            customTargetControl
                                .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .top)), reduceMotion: reduceMotion))
                        }
                        resultCard(isCompact: stackedTargets)
                        bestTimeCard
                        actionButtons
                        if !model.accelerationAttempts.isEmpty {
                            attemptHistory
                                .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .bottom)), reduceMotion: reduceMotion))
                        }
                    }
                    .padding(.horizontal, geometry.size.width < 380 ? 16 : 22)
                    .padding(.top, compact ? 4 : 10)
                    .padding(.bottom, 22)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                    .animation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion), value: model.accelerationPreset)
                    .animation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion), value: model.accelerationAttempts.map(\.id))
                }
            }
        }
        .preferredColorScheme(appearance.preferredColorScheme)
        .toolbar(.visible, for: .tabBar)
        .sensoryFeedback(.selection, trigger: model.accelerationPreset)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.accelerationState == .timing)
        .sensoryFeedback(.success, trigger: model.isNewAccelerationBest)
    }

    private var header: some View {
        VStack(spacing: 7) {
            Text("Acceleration test")
                .modifier(AdaptiveFont(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(SpeedometerStyle.foreground)
            Text("Measure your launch")
                .modifier(AdaptiveFont(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .frame(minHeight: 68)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func targetPicker(isStacked: Bool) -> some View {
        Group {
            if isStacked {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    presetTargetButton(20)
                    presetTargetButton(50)
                    presetTargetButton(100)
                    customTargetButton
                }
                .padding(5)
                .veluraGlassCard(cornerRadius: 20, stroke: SpeedometerStyle.foreground.opacity(0.11))
            } else {
                HStack(spacing: 4) {
                    presetTargetButton(20)
                    presetTargetButton(50)
                    presetTargetButton(100)
                    customTargetButton
                }
                .padding(5)
                .veluraGlassCapsule(stroke: SpeedometerStyle.foreground.opacity(0.11))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Acceleration target")
        .animation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion), value: model.accelerationPreset)
    }

    private func presetTargetButton(_ preset: Int) -> some View {
        targetButton(title: "0–\(displayedTarget(preset)) \(speedUnit)", isSelected: model.accelerationPreset == preset) {
            withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                model.selectAccelerationPreset(preset)
            }
        }
        .accessibilityLabel("Acceleration target zero to \(displayedTarget(preset)) \(spokenSpeedUnit)")
    }

    private var customTargetButton: some View {
        targetButton(title: "Custom", isSelected: model.accelerationPreset == -1) {
            withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                model.selectCustomAccelerationTarget(Double(model.customAccelerationTargetKmh))
            }
        }
        .accessibilityLabel("Custom acceleration target")
    }

    private func targetButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .modifier(AdaptiveFont(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(isSelected ? SpeedometerStyle.accentForeground : SpeedometerStyle.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .padding(.horizontal, 3)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(SpeedometerStyle.accent)
                            .overlay { Capsule().stroke(SpeedometerStyle.foreground.opacity(0.24), lineWidth: 1) }
                            .shadow(color: SpeedometerStyle.accent.opacity(0.3), radius: 10, y: 2)
                            .matchedGeometryEffect(id: "accelTargetSelection", in: targetSelectionNamespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(VeluraGlassPressButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var customTargetValue: some View {
        Text("\(target) \(speedUnit)")
            .modifier(AdaptiveFont(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(SpeedometerStyle.accent)
            .contentTransition(.numericText())
    }

    private var customTargetControl: some View {
        VStack(spacing: 5) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CUSTOM TARGET")
                            .modifier(AdaptiveFont(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(SpeedometerStyle.secondary)
                        customTargetValue
                    }
                } else {
                    HStack {
                        Text("CUSTOM TARGET")
                            .modifier(AdaptiveFont(size: 10, weight: .bold, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(SpeedometerStyle.secondary)
                        Spacer()
                        customTargetValue
                    }
                }
            }

            Slider(value: Binding(
                get: { Double(model.customAccelerationTargetKmh) * unitConversion },
                set: { model.selectCustomAccelerationTarget($0 / unitConversion) }
            ), in: (20 * unitConversion)...(240 * unitConversion), step: 5 * unitConversion)
            .tint(SpeedometerStyle.accent)
            .accessibilityLabel("Custom acceleration target in \(spokenSpeedUnit)")
            .accessibilityValue("\(Int((Double(model.customAccelerationTargetKmh) * unitConversion).rounded())) \(spokenSpeedUnit)")

            HStack {
                Text("\(Int((20 * unitConversion).rounded())) \(speedUnit)")
                Spacer()
                Text("\(Int((240 * unitConversion).rounded())) \(speedUnit)")
            }
            .modifier(AdaptiveFont(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(SpeedometerStyle.secondary.opacity(0.82))
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .veluraGlassCard(cornerRadius: 19, stroke: SpeedometerStyle.foreground.opacity(0.09))
        .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .top)), reduceMotion: reduceMotion))
    }

    private func resultCard(isCompact: Bool) -> some View {
        VStack(spacing: 17) {
            Text(stateTitle)
                .modifier(AdaptiveFont(size: 17, weight: .semibold, design: .rounded))
                .tracking(2.2)
                .foregroundStyle(model.accelerationState == .completed && model.isNewAccelerationBest ? SpeedometerStyle.mint : SpeedometerStyle.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)

            TimelineView(.animation(minimumInterval: 0.05, paused: model.accelerationState != .timing)) { context in
                let time = String(format: "%.2f", model.accelerationElapsed(at: context.date))
                let color = model.accelerationState == .completed ? SpeedometerStyle.accent : SpeedometerStyle.foreground
                Group {
                    if isCompact {
                        VStack(spacing: -4) {
                            Text(time)
                                .modifier(AdaptiveFont(size: 75, weight: .light, design: .rounded).monospacedDigit())
                                .foregroundStyle(color)
                                .contentTransition(.numericText())
                                .minimumScaleFactor(0.65)
                                .lineLimit(1)
                            Text("s")
                                .modifier(AdaptiveFont(size: 43, weight: .medium, design: .rounded))
                                .foregroundStyle(color)
                        }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(time)
                                .modifier(AdaptiveFont(size: 75, weight: .light, design: .rounded).monospacedDigit())
                                .foregroundStyle(color)
                                .contentTransition(.numericText())
                                .minimumScaleFactor(0.65)
                                .lineLimit(1)
                            Text("s")
                                .modifier(AdaptiveFont(size: 43, weight: .medium, design: .rounded))
                                .foregroundStyle(color)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Acceleration time")
                .accessibilityValue("\(time) seconds")
                .transaction { transaction in
                    transaction.animation = VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion)
                }
            }

            Text(stateDetail)
                .modifier(AdaptiveFont(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, minHeight: 226)
        .veluraGlassCard(
            cornerRadius: 26,
            tint: model.accelerationState == .completed && model.isNewAccelerationBest ? SpeedometerStyle.mint.opacity(0.14) : nil,
            stroke: SpeedometerStyle.foreground.opacity(0.12)
        )
        .accessibilityElement(children: .contain)
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.accelerationState)
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.isNewAccelerationBest)
    }

    private var bestTimeCard: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    bestTimeValue
                    if model.isNewAccelerationBest { newBestBadge }
                }
            } else {
                HStack(alignment: .center) {
                    bestTimeValue
                    Spacer(minLength: 8)
                    if model.isNewAccelerationBest { newBestBadge }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, minHeight: 93, alignment: .leading)
        .veluraGlassCard(cornerRadius: 24, stroke: SpeedometerStyle.foreground.opacity(0.1))
        .accessibilityElement(children: .combine)
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.isNewAccelerationBest)
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.bestAccelerationTime)
    }

    private var bestTimeValue: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BEST")
                .modifier(AdaptiveFont(size: 11, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(SpeedometerStyle.secondary)
            Text(model.bestAccelerationTime.map(accelerationTimeText) ?? "—")
                .modifier(AdaptiveFont(size: 27, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(model.isNewAccelerationBest ? SpeedometerStyle.mint : SpeedometerStyle.foreground)
                .contentTransition(.numericText())
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var newBestBadge: some View {
        Label("NEW BEST", systemImage: "sparkle")
            .modifier(AdaptiveFont(size: 9, weight: .bold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(SpeedometerStyle.mint)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(SpeedometerStyle.mint.opacity(0.1), in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
            .transition(VeluraMotion.transition(.opacity.combined(with: .scale(scale: 0.96)), reduceMotion: reduceMotion))
    }

    private var actionButtons: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                Button {
                    withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                        model.startAccelerationTest()
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: model.accelerationPrimaryActionSymbol)
                            .modifier(AdaptiveFont(size: 16, weight: .bold))
                            .foregroundStyle(SpeedometerStyle.accent)
                            .contentTransition(.symbolEffect(.replace))
                        Text(model.accelerationPrimaryActionTitle)
                            .modifier(AdaptiveFont(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(SpeedometerStyle.foreground)
                            .contentTransition(.opacity)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 60)
                    .contentShape(Capsule())
                    .veluraGlassCapsule(
                        tint: SpeedometerStyle.accent.opacity(0.28),
                        interactive: true,
                        stroke: SpeedometerStyle.accent.opacity(0.42)
                    )
                    .glassEffectID("accel-primary", in: actionsGlassNamespace)
                }
                .buttonStyle(VeluraGlassPressButtonStyle())
                .disabled(!model.isAccelerationPrimaryActionEnabled)
                .opacity(model.isAccelerationPrimaryActionEnabled ? 1 : 0.65)
                .accessibilityHint("Arms a GPS acceleration run when ready")

                Button {
                    withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                        model.resetAccelerationTest()
                    }
                } label: {
                    Text("Reset")
                        .modifier(AdaptiveFont(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .contentShape(Capsule())
                        .veluraGlassCapsule(interactive: true)
                        .glassEffectID("accel-reset", in: actionsGlassNamespace)
                }
                .buttonStyle(VeluraGlassPressButtonStyle())
                .accessibilityLabel("Reset acceleration test")
            }
        }
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.accelerationState)
    }

    private var attemptHistory: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .modifier(AdaptiveFont(size: 13, weight: .semibold))
                    .foregroundStyle(SpeedometerStyle.accent)
                Text("RECENT RUNS")
                    .modifier(AdaptiveFont(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(SpeedometerStyle.secondary)
                Spacer()
                Text("\(model.accelerationAttempts.count)")
                    .modifier(AdaptiveFont(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(SpeedometerStyle.secondary)
            }

            ForEach(model.accelerationAttemptGroups) { group in
                VStack(alignment: .leading, spacing: 9) {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("0–\(displayedTarget(group.targetKmh)) \(speedUnit)")
                                .modifier(AdaptiveFont(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(SpeedometerStyle.foreground)
                            Text("BEST · \(group.bestTime.map(accelerationTimeText) ?? "—")")
                                .modifier(AdaptiveFont(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(SpeedometerStyle.mint)
                        }
                    } else {
                        HStack {
                            Text("0–\(displayedTarget(group.targetKmh)) \(speedUnit)")
                                .modifier(AdaptiveFont(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(SpeedometerStyle.foreground)
                            Spacer()
                            Text(group.bestTime.map(accelerationTimeText) ?? "—")
                                .modifier(AdaptiveFont(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(SpeedometerStyle.mint)
                        }
                    }

                    ForEach(group.attempts) { attempt in
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 7) {
                                attemptDetails(attempt)
                                HStack {
                                    Spacer()
                                    deleteAttemptButton(attempt, targetKmh: group.targetKmh)
                                }
                            }
                        } else {
                            HStack(spacing: 10) {
                                attemptDetails(attempt)
                                Spacer(minLength: 4)
                                deleteAttemptButton(attempt, targetKmh: group.targetKmh)
                            }
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
        .veluraGlassCard(cornerRadius: 21)
    }

    private func attemptDetails(_ attempt: AccelerationAttempt) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(attempt.date.formatted(date: .abbreviated, time: .shortened))
                .modifier(AdaptiveFont(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.foreground.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)
            Text(accelerationTimeText(attempt.duration))
                .modifier(AdaptiveFont(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(SpeedometerStyle.secondary)
        }
    }

    private func deleteAttemptButton(_ attempt: AccelerationAttempt, targetKmh: Int) -> some View {
        Button(role: .destructive) {
            withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                model.deleteAccelerationAttempt(attempt.id)
            }
        } label: {
            Image(systemName: "trash")
                .modifier(AdaptiveFont(size: 12, weight: .semibold))
                .foregroundStyle(SpeedometerStyle.warning)
                .frame(width: 44, height: 44)
                .background(SpeedometerStyle.warning.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(VeluraGlassPressButtonStyle())
        .accessibilityLabel("Delete zero to \(displayedTarget(targetKmh)) \(spokenSpeedUnit) attempt")
    }

    private var stateTitle: String {
        model.accelerationStatusTitle
    }

    private var stateDetail: String {
        model.accelerationStatusDetail(target: target, unit: speedUnit)
    }

    private func accelerationTimeText(_ time: TimeInterval) -> String {
        String(format: "%.2f s", time)
    }
}
