import SwiftUI

private enum InsightsPeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }
    var previousLabel: String { self == .week ? "last week" : "last month" }
    var currentLabel: String { self == .week ? "this week" : "this month" }
}

private struct InsightBucket: Identifiable {
    let index: Int
    let start: Date
    let end: Date
    let distanceKm: Double
    let label: String
    let isCurrent: Bool

    var id: Int { index }
}

struct DrivingInsightsView: View {
    @ObservedObject private var appearance = AppAppearance.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var store = DriveHistoryStore.shared
    @AppStorage("speedometer.usesMiles") private var usesMiles = false
    @State private var selectedPeriod: InsightsPeriod = .week

    private var distanceUnit: String { usesMiles ? "mi" : "km" }
    private var speedUnit: String { usesMiles ? "mph" : "km/h" }
    private var conversion: Double { usesMiles ? 0.621371 : 1 }

    private var currentInterval: DateInterval {
        let component: Calendar.Component = selectedPeriod == .week ? .weekOfYear : .month
        var calendar = Calendar.current
        if selectedPeriod == .week { calendar.firstWeekday = 2 }
        return calendar.dateInterval(of: component, for: .now)
            ?? DateInterval(start: .now, end: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
    }

    private var previousInterval: DateInterval {
        let calendar = Calendar.current
        if selectedPeriod == .week {
            let end = currentInterval.start
            let start = calendar.date(byAdding: .day, value: -7, to: end) ?? end
            return DateInterval(start: start, end: end)
        }

        let previousMonth = calendar.date(byAdding: .month, value: -1, to: .now) ?? .now
        return calendar.dateInterval(of: .month, for: previousMonth)
            ?? DateInterval(start: calendar.date(byAdding: .month, value: -1, to: currentInterval.start) ?? currentInterval.start, end: currentInterval.start)
    }

    private var currentDrives: [DriveRecord] {
        store.drives.filter { $0.date >= currentInterval.start && $0.date < currentInterval.end }
    }

    private var previousDistanceKm: Double {
        store.drives
            .filter { $0.date >= previousInterval.start && $0.date < previousInterval.end }
            .reduce(0) { $0 + $1.distanceKm }
    }

    private var currentDistanceKm: Double {
        currentDrives.reduce(0) { $0 + $1.distanceKm }
    }

    private var averageDistanceKm: Double {
        guard !currentDrives.isEmpty else { return 0 }
        return currentDistanceKm / Double(currentDrives.count)
    }

    private var topSpeedKmh: Double? {
        currentDrives.map(\.topSpeedKmh).max()
    }

    private var comparisonSummary: String {
        guard previousDistanceKm > 0 else {
            return currentDistanceKm > 0 ? "First distance \(selectedPeriod.currentLabel)" : "No distance yet \(selectedPeriod.currentLabel)"
        }

        let change = (currentDistanceKm - previousDistanceKm) / previousDistanceKm * 100
        let percentage = Int(abs(change).rounded())
        if percentage == 0 { return "Same as \(selectedPeriod.previousLabel)" }
        return "\(percentage)% \(change > 0 ? "more" : "less") than \(selectedPeriod.previousLabel)"
    }

    private var comparisonSymbol: String {
        guard previousDistanceKm > 0 || currentDistanceKm > 0 else { return "minus" }
        if currentDistanceKm == previousDistanceKm { return "equal" }
        return currentDistanceKm > previousDistanceKm ? "arrow.up" : "arrow.down"
    }

    private var comparisonColor: Color {
        currentDistanceKm >= previousDistanceKm && currentDistanceKm > 0 ? SpeedometerStyle.mint : SpeedometerStyle.secondary
    }

    private var chartBuckets: [InsightBucket] {
        let calendar = Calendar.current
        let dayCount = max(1, calendar.dateComponents([.day], from: currentInterval.start, to: currentInterval.end).day ?? 7)
        let bucketCount = selectedPeriod == .week ? 7 : max(1, Int(ceil(Double(dayCount) / 7)))
        let now = Date.now

        return (0..<bucketCount).compactMap { index in
            let offset = selectedPeriod == .week ? index : index * 7
            guard let start = calendar.date(byAdding: .day, value: offset, to: currentInterval.start), start < currentInterval.end else { return nil }
            let nextOffset = selectedPeriod == .week ? offset + 1 : offset + 7
            let proposedEnd = calendar.date(byAdding: .day, value: nextOffset, to: currentInterval.start) ?? currentInterval.end
            let end = min(proposedEnd, currentInterval.end)
            let distance = currentDrives
                .filter { $0.date >= start && $0.date < end }
                .reduce(0) { $0 + $1.distanceKm }
            let label = selectedPeriod == .week
                ? start.formatted(.dateTime.weekday(.abbreviated))
                : "\(calendar.component(.day, from: start))"

            return InsightBucket(
                index: index,
                start: start,
                end: end,
                distanceKm: distance,
                label: label,
                isCurrent: now >= start && now < end
            )
        }
    }

    private var chartAxisStep: Double {
        let maximum = (chartBuckets.map { $0.distanceKm * conversion }.max() ?? 0) / 3
        if maximum <= 5 { return 5 }
        if maximum <= 10 { return 10 }
        return ceil(maximum / 5) * 5
    }

    private var chartAxisMaximum: Double { chartAxisStep * 3 }
    private var chartBucketSpacing: CGFloat {
        chartBuckets.count > 5 ? (dynamicTypeSize.isAccessibilitySize ? 3 : 12) : 18
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SpeedometerStyle.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        header

                        if store.drives.isEmpty {
                            emptyState
                                .padding(.top, 42)
                                .transition(VeluraMotion.transition(.opacity.combined(with: .scale(scale: 0.98)), reduceMotion: reduceMotion))
                        } else {
                            distanceSummary
                                .padding(.top, 28)
                                .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .top)), reduceMotion: reduceMotion))
                            distanceChart(height: geometry.size.width > geometry.size.height ? 156 : 228)
                                .padding(.top, 25)
                                .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .bottom)), reduceMotion: reduceMotion))
                            metricsSummary
                                .padding(.top, 24)
                                .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .bottom)), reduceMotion: reduceMotion))
                        }
                    }
                    .padding(.horizontal, geometry.size.width < 380 ? 16 : 22)
                    .padding(.top, 12)
                    .padding(.bottom, 30)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.visible, for: .tabBar)
        .preferredColorScheme(appearance.theme.colorScheme)
        .animation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion), value: selectedPeriod)
        .animation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion), value: store.drives.count)
    }

    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    backButton
                    Text("Driving insights")
                        .modifier(AdaptiveFont(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                periodPicker
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
            }
        } else {
            HStack(spacing: 7) {
                backButton
                Text("Driving insights")
                    .modifier(AdaptiveFont(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                periodPicker
                    .frame(width: 136, height: 48)
            }
            .frame(minHeight: 48)
        }
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .modifier(AdaptiveFont(size: 15, weight: .semibold))
                .foregroundStyle(SpeedometerStyle.foreground)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to drives")
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
                        .foregroundStyle(isSelected ? AppAppearance.shared.theme.accentForeground : SpeedometerStyle.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [
                                            SpeedometerStyle.accent.opacity(0.94),
                                            SpeedometerStyle.accent.opacity(0.78)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ))
                                    .overlay {
                                        Capsule().stroke(SpeedometerStyle.foreground.opacity(0.2), lineWidth: 1)
                                    }
                                    .shadow(color: SpeedometerStyle.accent.opacity(0.24), radius: 7, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(SpeedometerStyle.foreground.opacity(0.045), in: Capsule())
        .glassEffect(.regular, in: .capsule)
        .overlay {
            Capsule().stroke(SpeedometerStyle.foreground.opacity(0.09), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Insights period")
    }

    private var distanceSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selectedPeriod == .week ? "THIS WEEK" : "THIS MONTH")
                .modifier(AdaptiveFont(size: 12, weight: .semibold, design: .rounded))
                .tracking(1.35)
                .foregroundStyle(SpeedometerStyle.secondary)

            Text("\(String(format: "%.1f", currentDistanceKm * conversion)) \(distanceUnit)")
                .modifier(AdaptiveFont(size: 43, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(SpeedometerStyle.foreground)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: comparisonSymbol)
                    .modifier(AdaptiveFont(size: 14, weight: .bold))
                Text(comparisonSummary)
                    .modifier(AdaptiveFont(size: 15, weight: .semibold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(comparisonColor)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func distanceChart(height: CGFloat) -> some View {
        VStack(spacing: 8) {
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
                                let height = value > 0
                                    ? max(4, geometry.size.height * CGFloat(value / chartAxisMaximum))
                                    : 0
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(LinearGradient(
                                        colors: bucket.isCurrent
                                            ? [SpeedometerStyle.accent, SpeedometerStyle.accent.opacity(0.78)]
                                            : [SpeedometerStyle.accent.opacity(0.88), SpeedometerStyle.accent.opacity(0.58)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ))
                                    .frame(height: height)
                                    .frame(maxWidth: .infinity)
                                    .shadow(color: bucket.isCurrent ? SpeedometerStyle.accent.opacity(0.18) : .clear, radius: 8, y: 1)
                            }
                        }
                        .padding(.horizontal, 13)
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
                    Text(bucket.label)
                        .modifier(AdaptiveFont(size: 11, weight: bucket.isCurrent ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(bucket.isCurrent ? SpeedometerStyle.foreground : SpeedometerStyle.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background {
                            if bucket.isCurrent {
                                Capsule()
                                    .fill(SpeedometerStyle.foreground.opacity(0.085))
                                    .glassEffect(.regular, in: .capsule)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(bucket.label), \(String(format: "%.1f", bucket.distanceKm * conversion)) \(distanceUnit)")
                }
            }
            .padding(.trailing, dynamicTypeSize.isAccessibilitySize ? 64 : 30)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(selectedPeriod == .week ? "Distance by day" : "Distance by week")
    }

    private var metricsSummary: some View {
        let drivesMetric = metric(value: "\(currentDrives.count)", label: "DRIVES")
        let averageMetric = metric(value: currentDrives.isEmpty ? "—" : "\(String(format: "%.1f", averageDistanceKm * conversion)) \(distanceUnit)", label: "AVG. DISTANCE")
        let speedMetric = metric(value: topSpeedKmh.map { "\(String(format: "%.0f", $0 * conversion)) \(speedUnit)" } ?? "—", label: "TOP SPEED")

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    drivesMetric
                    Rectangle().fill(SpeedometerStyle.foreground.opacity(0.15)).frame(height: 1)
                    averageMetric
                    Rectangle().fill(SpeedometerStyle.foreground.opacity(0.15)).frame(height: 1)
                    speedMetric
                }
            } else {
                HStack(spacing: 0) {
                    drivesMetric
                    metricDivider
                    averageMetric
                    metricDivider
                    speedMetric
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 20)
        .background(SpeedometerStyle.foreground.opacity(0.035), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(SpeedometerStyle.foreground.opacity(0.11), lineWidth: 1)
        }
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(SpeedometerStyle.foreground.opacity(0.15))
            .frame(width: 1, height: 46)
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value)
                .modifier(AdaptiveFont(size: 21, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(SpeedometerStyle.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Text(label)
                .modifier(AdaptiveFont(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(SpeedometerStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 10)
        .accessibilityElement(children: .combine)
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

            Text("Save a drive from the Speed tab to see your distance trends, average drive and top speed here. Your history stays on this device.")
                .modifier(AdaptiveFont(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 36)
        .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

#Preview {
    NavigationStack {
        DrivingInsightsView()
    }
}
