import SwiftUI

private enum InsightsPeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }
    var previousLabel: String { self == .week ? "last week" : "last month" }
    var chartTitle: String { self == .week ? "DISTANCE BY DAY" : "DISTANCE BY WEEK" }
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
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = DriveHistoryStore.shared
    @AppStorage("speedometer.usesMiles") private var usesMiles = false
    @State private var selectedPeriod: InsightsPeriod = .week

    private var distanceUnit: String { usesMiles ? "mi" : "km" }
    private var speedUnit: String { usesMiles ? "mph" : "km/h" }
    private var conversion: Double { usesMiles ? 0.621371 : 1 }

    private var currentInterval: DateInterval {
        let component: Calendar.Component = selectedPeriod == .week ? .weekOfYear : .month
        return Calendar.current.dateInterval(of: component, for: .now)
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
            return currentDistanceKm > 0 ? "First distance \(selectedPeriod == .week ? "this week" : "this month")" : "No distance in either period"
        }

        let change = (currentDistanceKm - previousDistanceKm) / previousDistanceKm * 100
        let arrow = change >= 0 ? "↑" : "↓"
        return "\(arrow) \(Int(abs(change).rounded()))% vs \(selectedPeriod.previousLabel)"
    }

    private var comparisonColor: Color {
        if currentDistanceKm == 0 && previousDistanceKm == 0 { return SpeedometerStyle.secondary }
        return currentDistanceKm > previousDistanceKm ? SpeedometerStyle.mint : SpeedometerStyle.secondary
    }

    private var comparisonSymbol: String {
        if currentDistanceKm == 0 && previousDistanceKm == 0 { return "minus" }
        return currentDistanceKm >= previousDistanceKm ? "arrow.up.right" : "arrow.down.right"
    }

    private var periodCaption: String {
        if selectedPeriod == .month {
            return currentInterval.start.formatted(.dateTime.month(.wide).year()).uppercased()
        }
        let finalDay = Calendar.current.date(byAdding: .second, value: -1, to: currentInterval.end) ?? currentInterval.end
        return "\(currentInterval.start.formatted(.dateTime.month(.abbreviated).day())) – \(finalDay.formatted(.dateTime.month(.abbreviated).day()))"
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
                ? start.formatted(.dateTime.weekday(.narrow))
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

    var body: some View {
        ZStack {
            SpeedometerStyle.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 17) {
                    header
                    periodPicker

                    if store.drives.isEmpty {
                        emptyState
                    } else {
                        distanceSummary
                        distanceChart
                        metricsSummary
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 30)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .animation(.snappy(duration: 0.3), value: selectedPeriod)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to drive history")

            VStack(alignment: .leading, spacing: 3) {
                Text("Driving insights")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Your driving, at a glance")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(height: 46)
    }

    private var periodPicker: some View {
        HStack(spacing: 5) {
            ForEach(InsightsPeriod.allCases) { period in
                let isSelected = selectedPeriod == period
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) {
                        selectedPeriod = period
                    }
                } label: {
                    Text(period.rawValue)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : SpeedometerStyle.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(SpeedometerStyle.accent.opacity(0.17))
                                    .glassEffect(.regular.tint(SpeedometerStyle.accent.opacity(0.22)), in: .capsule)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(5)
        .background(.white.opacity(0.025), in: Capsule())
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Insights period")
    }

    private var distanceSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedPeriod == .week ? "THIS WEEK" : "THIS MONTH")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(SpeedometerStyle.secondary)
                Spacer()
                Text(periodCaption)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(String(format: "%.1f", currentDistanceKm * conversion))
                    .font(.system(size: 43, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(distanceUnit)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
                Spacer(minLength: 0)
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(SpeedometerStyle.accent)
                    .frame(width: 46, height: 46)
                    .background(SpeedometerStyle.accent.opacity(0.1), in: Circle())
            }

            HStack(spacing: 6) {
                Image(systemName: comparisonSymbol)
                    .font(.system(size: 10, weight: .bold))
                Text(comparisonSummary)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Text("\(String(format: "%.1f", previousDistanceKm * conversion)) \(distanceUnit) prior")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(comparisonColor)
        }
        .padding(16)
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 23))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(selectedPeriod == .week ? "This week" : "This month"), \(String(format: "%.1f", currentDistanceKm * conversion)) \(distanceUnit), \(comparisonSummary), previous period \(String(format: "%.1f", previousDistanceKm * conversion)) \(distanceUnit)")
    }

    private var distanceChart: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SpeedometerStyle.accent)
                Text(selectedPeriod.chartTitle)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(SpeedometerStyle.secondary)
                Spacer()
                Text("\(String(format: "%.1f", currentDistanceKm * conversion)) \(distanceUnit)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.86))
            }

            HStack(alignment: .bottom, spacing: 8) {
                let maximum = chartBuckets.map(\.distanceKm).max() ?? 0
                ForEach(chartBuckets) { bucket in
                    VStack(spacing: 7) {
                        GeometryReader { geometry in
                            let height = maximum > 0
                                ? max(4, geometry.size.height * CGFloat(bucket.distanceKm / maximum))
                                : 3
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(bucket.isCurrent ? SpeedometerStyle.accent : SpeedometerStyle.accent.opacity(bucket.distanceKm > 0 ? 0.48 : 0.12))
                                .frame(height: height)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                .shadow(color: bucket.isCurrent ? SpeedometerStyle.accent.opacity(0.25) : .clear, radius: 7)
                        }
                        .frame(height: 92)

                        Text(bucket.label)
                            .font(.system(size: 10, weight: bucket.isCurrent ? .bold : .medium, design: .rounded))
                            .foregroundStyle(bucket.isCurrent ? SpeedometerStyle.accent : SpeedometerStyle.secondary)
                            .frame(height: 13)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(bucket.label), \(String(format: "%.1f", bucket.distanceKm * conversion)) \(distanceUnit)")
                }
            }
            .frame(height: 112)

            if currentDrives.isEmpty {
                Text("No drives recorded \(selectedPeriod == .week ? "this week" : "this month") yet. Your activity will appear here.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
            }
        }
        .padding(15)
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 23))
    }

    private var metricsSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DRIVE SUMMARY")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(SpeedometerStyle.secondary)

            HStack(spacing: 0) {
                metric(value: "\(currentDrives.count)", unit: "", label: "DRIVES", symbol: "car.side.fill", tint: SpeedometerStyle.accent)
                metricDivider
                metric(value: currentDrives.isEmpty ? "—" : String(format: "%.1f", averageDistanceKm * conversion), unit: currentDrives.isEmpty ? "" : distanceUnit, label: "AVG DISTANCE", symbol: "arrow.left.and.right", tint: SpeedometerStyle.mint)
                metricDivider
                metric(value: topSpeedKmh.map { String(format: "%.0f", $0 * conversion) } ?? "—", unit: topSpeedKmh == nil ? "" : speedUnit, label: "TOP SPEED", symbol: "speedometer", tint: SpeedometerStyle.accent)
            }
        }
        .padding(15)
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 23))
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(width: 1, height: 54)
    }

    private func metric(value: String, unit: String, label: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 19, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                }
            }
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.55)
                .foregroundStyle(SpeedometerStyle.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 13) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(SpeedometerStyle.accent)
                .frame(width: 66, height: 66)
                .background(SpeedometerStyle.accent.opacity(0.1), in: Circle())

            Text("Your insights start with a drive")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("Save a drive from the Speed tab to see your distance trends, average drive and top speed here. Your history stays on this device.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 36)
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

#Preview {
    NavigationStack {
        DrivingInsightsView()
    }
}
