import SwiftUI

struct DrivingInsightsView: View {
    @ObservedObject private var appearance = AppAppearance.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var store = DriveHistoryStore.shared
    @AppStorage("speedometer.usesMiles") private var usesMiles = false
    @State private var selectedPeriod: InsightsPeriod = .week
    @State private var selectedBucketIndex: Int?
    @State private var hasAppeared = false
    @Namespace private var periodSelectionNamespace

    private var distanceUnit: String { usesMiles ? "mi" : "km" }
    private var speedUnit: String { usesMiles ? "mph" : "km/h" }
    private var elevationUnit: String { usesMiles ? "ft" : "m" }
    private var conversion: Double { usesMiles ? 0.621371 : 1 }
    private var elevationConversion: Double { usesMiles ? 3.28084 : 1 }

    private var currentDrives: [DriveRecord] {
        DrivingInsightsCalculator.drives(in: selectedPeriod, from: store.drives)
    }

    private var summary: DrivingInsightsSummary {
        DrivingInsightsCalculator.summarize(drives: currentDrives)
    }

    private var previousDistanceKm: Double? {
        guard let previous = DrivingInsightsCalculator.previousInterval(for: selectedPeriod) else { return nil }
        return store.drives
            .filter { $0.date >= previous.start && $0.date < previous.end }
            .reduce(0) { $0 + $1.distanceKm }
    }

    private var comparisonSummary: String {
        guard let previousLabel = selectedPeriod.previousLabel, let previousDistanceKm else {
            return summary.driveCount > 0
                ? "\(summary.driveCount) \(summary.driveCount == 1 ? "drive" : "drives") recorded on this device"
                : "No drives recorded yet"
        }
        guard previousDistanceKm > 0 else {
            return summary.totalDistanceKm > 0
                ? "First distance \(selectedPeriod.currentLabel)"
                : "No distance yet \(selectedPeriod.currentLabel)"
        }

        let change = (summary.totalDistanceKm - previousDistanceKm) / previousDistanceKm * 100
        let percentage = Int(abs(change).rounded())
        if percentage == 0 { return "Same as \(previousLabel)" }
        return "\(percentage)% \(change > 0 ? "more" : "less") than \(previousLabel)"
    }

    private var comparisonSymbol: String {
        guard let previousDistanceKm else { return "chart.line.uptrend.xyaxis" }
        guard previousDistanceKm > 0 || summary.totalDistanceKm > 0 else { return "minus" }
        if summary.totalDistanceKm == previousDistanceKm { return "equal" }
        return summary.totalDistanceKm > previousDistanceKm ? "arrow.up" : "arrow.down"
    }

    private var comparisonColor: Color {
        guard let previousDistanceKm else { return SpeedometerStyle.accent }
        return summary.totalDistanceKm >= previousDistanceKm && summary.totalDistanceKm > 0
            ? SpeedometerStyle.mint
            : SpeedometerStyle.secondary
    }

    private var chartBuckets: [InsightBucket] {
        DrivingInsightsCalculator.buckets(for: selectedPeriod, drives: currentDrives)
    }

    private var selectedBucket: InsightBucket? {
        guard let selectedBucketIndex else { return nil }
        return chartBuckets.first(where: { $0.index == selectedBucketIndex })
    }

    private var latestElevationDrive: (drive: DriveRecord, elevation: ElevationSummary)? {
        for drive in currentDrives {
            if let elevation = DrivingInsightsCalculator.elevationProfile(for: drive) {
                return (drive, elevation)
            }
        }
        return nil
    }

    private var chartAxisStep: Double {
        let maximum = (chartBuckets.map { $0.distanceKm * conversion }.max() ?? 0) / 3
        if maximum <= 5 { return 5 }
        if maximum <= 10 { return 10 }
        return ceil(maximum / 5) * 5
    }

    private var chartAxisMaximum: Double { chartAxisStep * 3 }
    private var chartBucketSpacing: CGFloat {
        chartBuckets.count > 5 ? (dynamicTypeSize.isAccessibilitySize ? 3 : 10) : 14
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VeluraAmbientBackdrop(intensity: 0.16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        periodPicker

                        if store.drives.isEmpty {
                            emptyState
                                .padding(.top, 24)
                                .transition(VeluraMotion.transition(.opacity.combined(with: .scale(scale: 0.98)), reduceMotion: reduceMotion))
                        } else {
                            distanceSummary
                                .padding(.top, 6)
                                .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .top)), reduceMotion: reduceMotion))

                            if currentDrives.isEmpty {
                                periodEmptyState
                                    .transition(VeluraMotion.transition(.opacity.combined(with: .scale(scale: 0.98)), reduceMotion: reduceMotion))
                            } else {
                                distanceChart(height: geometry.size.width > geometry.size.height ? 156 : 216)
                                    .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .bottom)), reduceMotion: reduceMotion))

                                metricsGrid
                                    .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .bottom)), reduceMotion: reduceMotion))

                                if let latestElevation = latestElevationDrive {
                                    elevationSection(drive: latestElevation.drive, elevation: latestElevation.elevation)
                                        .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .bottom)), reduceMotion: reduceMotion))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, geometry.size.width < 380 ? 16 : 22)
                    .padding(.top, 12)
                    .padding(.bottom, 30)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .toolbarVisibility(.visible, for: .navigationBar)
        .toolbarVisibility(.visible, for: .tabBar)
        .navigationTitle("Driving insights")
        .navigationBarTitleDisplayMode(.inline)
        .scrollEdgeEffectStyle(.soft, for: .top)
        .preferredColorScheme(appearance.preferredColorScheme)
        .sensoryFeedback(.selection, trigger: selectedPeriod)
        .sensoryFeedback(.selection, trigger: selectedBucketIndex)
        .animation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion), value: selectedPeriod)
        .animation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion), value: selectedBucketIndex)
        .animation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion), value: store.drives.count)
        .onChange(of: selectedPeriod) { _, _ in
            selectedBucketIndex = nil
        }
        .onAppear {
            withAnimation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion)) {
                hasAppeared = true
            }
        }
    }

    private var periodPicker: some View {
        HStack(spacing: 3) {
            ForEach(InsightsPeriod.allCases) { period in
                let isSelected = selectedPeriod == period
                Button {
                    withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                        selectedPeriod = period
                    }
                } label: {
                    Text(period.rawValue)
                        .modifier(AdaptiveFont(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? SpeedometerStyle.accentForeground : SpeedometerStyle.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [
                                            SpeedometerStyle.accent.opacity(0.96),
                                            SpeedometerStyle.accent.opacity(0.8)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ))
                                    .overlay {
                                        Capsule().stroke(SpeedometerStyle.foreground.opacity(0.2), lineWidth: 1)
                                    }
                                    .shadow(color: SpeedometerStyle.accent.opacity(0.24), radius: 7, y: 2)
                                    .matchedGeometryEffect(id: "insightsPeriodSelection", in: periodSelectionNamespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(VeluraGlassPressButtonStyle())
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Insights period")
    }

    private var distanceSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectedPeriod.sectionTitle)
                .modifier(AdaptiveFont(size: 12, weight: .semibold, design: .rounded))
                .tracking(1.35)
                .foregroundStyle(SpeedometerStyle.secondary)

            Text("\(String(format: "%.1f", summary.totalDistanceKm * conversion)) \(distanceUnit)")
                .modifier(AdaptiveFont(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(SpeedometerStyle.foreground)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: comparisonSymbol)
                    .modifier(AdaptiveFont(size: 14, weight: .bold))
                Text(comparisonSummary)
                    .modifier(AdaptiveFont(size: 14, weight: .semibold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(comparisonColor)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func distanceChart(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let bucket = selectedBucket {
                bucketTooltip(bucket)
                    .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .top)), reduceMotion: reduceMotion))
            } else {
                Text("Tap a bar to inspect exact values")
                    .modifier(AdaptiveFont(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        Canvas { context, size in
                            for tick in 0...3 {
                                let y = size.height - CGFloat(tick) * size.height / 3
                                var line = Path()
                                line.move(to: CGPoint(x: 0, y: y))
                                line.addLine(to: CGPoint(x: size.width, y: y))
                                let style = tick == 0
                                    ? StrokeStyle(lineWidth: 1)
                                    : StrokeStyle(lineWidth: 1, dash: [2, 5])
                                context.stroke(line, with: .color(SpeedometerStyle.foreground.opacity(tick == 0 ? 0.24 : 0.13)), style: style)
                            }
                        }

                        HStack(alignment: .bottom, spacing: chartBucketSpacing) {
                            ForEach(chartBuckets) { bucket in
                                let value = bucket.distanceKm * conversion
                                let targetHeight = value > 0
                                    ? max(6, geometry.size.height * CGFloat(value / chartAxisMaximum))
                                    : 0
                                let isSelected = selectedBucketIndex == bucket.index
                                let isDimmed = selectedBucketIndex != nil && !isSelected

                                Button {
                                    withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                                        selectedBucketIndex = isSelected ? nil : bucket.index
                                    }
                                } label: {
                                    VStack(spacing: 0) {
                                        Spacer(minLength: 0)
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .fill(LinearGradient(
                                                colors: (isSelected || bucket.isCurrent)
                                                    ? [SpeedometerStyle.accent, SpeedometerStyle.mint.opacity(0.86)]
                                                    : [SpeedometerStyle.accent.opacity(0.84), SpeedometerStyle.accent.opacity(0.5)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            ))
                                            .opacity(isDimmed ? 0.38 : 1)
                                            .frame(height: hasAppeared || reduceMotion ? targetHeight : 0)
                                            .shadow(color: isSelected ? SpeedometerStyle.accent.opacity(0.36) : .clear, radius: 10, y: 2)
                                            .animation(
                                                VeluraMotion.animation(
                                                    VeluraMotion.content.delay(Double(bucket.index) * 0.03),
                                                    reduceMotion: reduceMotion
                                                ),
                                                value: hasAppeared
                                            )
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(bucket.detailLabel), \(String(format: "%.1f", value)) \(distanceUnit), \(bucket.driveCount) drives")
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }
                        .padding(.horizontal, 10)
                    }
                }
                .frame(height: height)

                GeometryReader { geometry in
                    ZStack {
                        ForEach(0...3, id: \.self) { tick in
                            Text("\(Int(chartAxisStep * Double(3 - tick)))")
                                .modifier(AdaptiveFont(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                                .foregroundStyle(SpeedometerStyle.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .position(
                                    x: geometry.size.width / 2,
                                    y: 8 + CGFloat(tick) * max(0, geometry.size.height - 16) / 3
                                )
                        }
                    }
                }
                .frame(width: dynamicTypeSize.isAccessibilitySize ? 64 : 30, height: height)
            }

            HStack(spacing: chartBucketSpacing) {
                ForEach(chartBuckets) { bucket in
                    let isHighlighted = selectedBucketIndex == bucket.index || (selectedBucketIndex == nil && bucket.isCurrent)
                    Button {
                        withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                            selectedBucketIndex = selectedBucketIndex == bucket.index ? nil : bucket.index
                        }
                    } label: {
                        Text(bucket.label)
                            .modifier(AdaptiveFont(size: 11, weight: isHighlighted ? .semibold : .medium, design: .rounded))
                            .foregroundStyle(isHighlighted ? SpeedometerStyle.foreground : SpeedometerStyle.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 40)
                            .background {
                                if isHighlighted {
                                    Capsule()
                                        .fill(SpeedometerStyle.accent.opacity(selectedBucketIndex == bucket.index ? 0.24 : 0.11))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)
                }
            }
            .padding(.trailing, dynamicTypeSize.isAccessibilitySize ? 64 : 30)
        }
        .padding(16)
        .veluraContentCard(cornerRadius: 24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Distance chart for \(selectedPeriod.currentLabel)")
    }

    private func bucketTooltip(_ bucket: InsightBucket) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(bucket.detailLabel)
                    .modifier(AdaptiveFont(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.foreground)
                Text("\(bucket.driveCount) \(bucket.driveCount == 1 ? "drive" : "drives") · \(insightsDuration(bucket.duration))")
                    .modifier(AdaptiveFont(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
            }
            Spacer()
            Text("\(String(format: "%.1f", bucket.distanceKm * conversion)) \(distanceUnit)")
                .modifier(AdaptiveFont(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(SpeedometerStyle.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SpeedometerStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var metricsGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        return LazyVGrid(columns: columns, spacing: 10) {
            metricTile(
                title: "DRIVES",
                value: "\(summary.driveCount)",
                symbol: "car.fill"
            )
            metricTile(
                title: "AVG. DISTANCE",
                value: "\(String(format: "%.1f", summary.averageDriveDistanceKm * conversion)) \(distanceUnit)",
                symbol: "point.topleft.down.to.point.bottomright.curvepath"
            )
            metricTile(
                title: "AVG. SPEED",
                value: summary.averageSpeedKmh > 0 ? "\(Int((summary.averageSpeedKmh * conversion).rounded())) \(speedUnit)" : "—",
                symbol: "speedometer"
            )
            metricTile(
                title: "TOP SPEED",
                value: summary.topSpeedKmh.map { "\(Int(($0 * conversion).rounded())) \(speedUnit)" } ?? "—",
                symbol: "flame.fill"
            )
            metricTile(
                title: "TOTAL TIME",
                value: insightsDuration(summary.totalDuration),
                symbol: "clock.fill"
            )
            metricTile(
                title: "MOVING TIME",
                value: summary.hasMovingDurationData ? insightsDuration(summary.movingDuration) : "—",
                symbol: "figure.walk.motion"
            )
            if let gain = summary.elevationGainMeters, let loss = summary.elevationLossMeters {
                metricTile(
                    title: "ELEVATION GAIN",
                    value: "+\(Int((gain * elevationConversion).rounded())) \(elevationUnit)",
                    symbol: "arrow.up.right"
                )
                metricTile(
                    title: "ELEVATION LOSS",
                    value: "-\(Int((loss * elevationConversion).rounded())) \(elevationUnit)",
                    symbol: "arrow.down.right"
                )
            }
        }
    }

    private func metricTile(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .modifier(AdaptiveFont(size: 11, weight: .semibold))
                    .foregroundStyle(SpeedometerStyle.accent)
                Text(title)
                    .modifier(AdaptiveFont(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(SpeedometerStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Text(value)
                .modifier(AdaptiveFont(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(SpeedometerStyle.foreground)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .veluraContentCard(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }

    private func elevationSection(drive: DriveRecord, elevation: ElevationSummary) -> some View {
        let gainText = "+\(Int((elevation.gainMeters * elevationConversion).rounded())) \(elevationUnit)"
        let lossText = "-\(Int((elevation.lossMeters * elevationConversion).rounded())) \(elevationUnit)"
        let minText = "\(Int((elevation.minMeters * elevationConversion).rounded())) \(elevationUnit)"
        let maxText = "\(Int((elevation.maxMeters * elevationConversion).rounded())) \(elevationUnit)"

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LATEST ELEVATION PROFILE")
                        .modifier(AdaptiveFont(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(SpeedometerStyle.secondary)
                    Text(drive.date.formatted(date: .abbreviated, time: .shortened))
                        .modifier(AdaptiveFont(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                }
                Spacer()
                Text("\(gainText) · \(lossText)")
                    .modifier(AdaptiveFont(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(SpeedometerStyle.accent)
            }

            Canvas { context, size in
                let samples = elevation.samples
                guard samples.count >= 2 else { return }
                let span = max(1, elevation.maxMeters - elevation.minMeters)

                var strokePath = Path()
                var areaPath = Path()
                for (index, sample) in samples.enumerated() {
                    let x = CGFloat(index) / CGFloat(samples.count - 1) * size.width
                    let normalized = (sample.altitudeMeters - elevation.minMeters) / span
                    let y = size.height - CGFloat(normalized) * (size.height - 10) - 5
                    if index == 0 {
                        strokePath.move(to: CGPoint(x: x, y: y))
                        areaPath.move(to: CGPoint(x: x, y: size.height))
                        areaPath.addLine(to: CGPoint(x: x, y: y))
                    } else {
                        strokePath.addLine(to: CGPoint(x: x, y: y))
                        areaPath.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                areaPath.addLine(to: CGPoint(x: size.width, y: size.height))
                areaPath.closeSubpath()

                context.fill(
                    areaPath,
                    with: .linearGradient(
                        Gradient(colors: [SpeedometerStyle.accent.opacity(0.32), .clear]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
                context.stroke(
                    strokePath,
                    with: .color(SpeedometerStyle.accent),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                )
            }
            .frame(height: 82)

            HStack {
                Text("Min \(minText)")
                Spacer()
                Text("Max \(maxText)")
            }
            .modifier(AdaptiveFont(size: 10, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(SpeedometerStyle.secondary)
        }
        .padding(16)
        .veluraContentCard(cornerRadius: 24)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Latest elevation profile, gain \(gainText), loss \(lossText), range \(minText) to \(maxText)")
    }

    private var periodEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .modifier(AdaptiveFont(size: 26, weight: .light))
                .foregroundStyle(SpeedometerStyle.accent)
            Text("No drives \(selectedPeriod.currentLabel)")
                .modifier(AdaptiveFont(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(SpeedometerStyle.foreground)
            Text("Switch periods to inspect earlier driving activity.")
                .modifier(AdaptiveFont(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 32)
        .veluraContentCard(cornerRadius: 24)
    }

    private var emptyState: some View {
        VStack(spacing: 13) {
            Image(systemName: "chart.xyaxis.line")
                .modifier(AdaptiveFont(size: 30, weight: .light))
                .foregroundStyle(SpeedometerStyle.accent)
                .frame(width: 66, height: 66)
                .background(SpeedometerStyle.accent.opacity(0.1), in: Circle())

            Text("Your insights start with a drive")
                .modifier(AdaptiveFont(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(SpeedometerStyle.foreground)
                .multilineTextAlignment(.center)

            Text("Save a drive from the Speed tab to see your distance trends, speed averages, elevation and totals here. Your history stays on this device.")
                .modifier(AdaptiveFont(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 36)
        .veluraContentCard(cornerRadius: 24)
    }
}

private func insightsDuration(_ duration: TimeInterval) -> String {
    let totalMinutes = max(0, Int(duration / 60))
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(minutes)m"
}

#Preview {
    NavigationStack {
        DrivingInsightsView()
    }
}
