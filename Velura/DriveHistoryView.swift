import Foundation
import SwiftUI

private enum HistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case thisWeek = "This week"
    case thisMonth = "This month"

    var id: String { rawValue }
}

private struct DriveDayGroup: Identifiable {
    let date: Date
    let title: String
    let drives: [DriveRecord]

    var id: Date { date }
}

struct DriveHistoryView: View {
    @ObservedObject private var appearance = AppAppearance.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var store = DriveHistoryStore.shared
    @State private var filter: HistoryFilter = .all
    @State private var searchText = ""
    @State private var showingClearConfirmation = false
    @State private var isSearchPresented = false
    @State private var showingInsights = false
    @AppStorage("speedometer.usesMiles") private var usesMiles = false

    private var distanceUnit: String { usesMiles ? "mi" : "km" }
    private var conversion: Double { usesMiles ? 0.621371 : 1 }

    private var monthDrives: [DriveRecord] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: .now) else { return [] }
        return store.drives.filter { interval.contains($0.date) }
    }

    private var filteredDrives: [DriveRecord] {
        let calendar = Calendar.current
        let now = Date.now
        let dateFilteredDrives: [DriveRecord]
        switch filter {
        case .all:
            dateFilteredDrives = store.drives
        case .thisWeek:
            if let interval = calendar.dateInterval(of: .weekOfYear, for: now) {
                dateFilteredDrives = store.drives.filter { interval.contains($0.date) }
            } else {
                dateFilteredDrives = store.drives
            }
        case .thisMonth:
            if let interval = calendar.dateInterval(of: .month, for: now) {
                dateFilteredDrives = store.drives.filter { interval.contains($0.date) }
            } else {
                dateFilteredDrives = store.drives
            }
        }

        let query = normalizedSearchQuery
        guard !query.isEmpty else { return dateFilteredDrives }
        return dateFilteredDrives.filter { searchableText(for: $0).contains(query) }
    }

    private var normalizedSearchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private var dayGroups: [DriveDayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredDrives) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            DriveDayGroup(date: day, title: dayTitle(for: day), drives: grouped[day] ?? [])
        }
    }

    private func dayTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "TODAY"
        }
        if calendar.isDateInYesterday(date) {
            return "YESTERDAY"
        }
        return date.formatted(.dateTime.month(.wide).day().year())
    }

    private func searchableText(for drive: DriveRecord) -> String {
        let dateValues = [
            dayTitle(for: drive.date),
            drive.date.formatted(date: .omitted, time: .shortened),
            drive.date.formatted(date: .complete, time: .shortened),
            drive.date.formatted(date: .long, time: .shortened),
            drive.date.formatted(date: .abbreviated, time: .shortened),
            drive.date.formatted(date: .numeric, time: .shortened)
        ]
        let values = dateValues + [
            String(format: "%.1f km", drive.distanceKm),
            String(format: "%.2f km", drive.distanceKm),
            String(format: "%.1f mi", drive.distanceKm * 0.621371),
            String(format: "%.2f mi", drive.distanceKm * 0.621371),
            rowDuration(drive.duration),
            detailedDuration(drive.duration),
            "\(Int(drive.topSpeedKmh.rounded())) km/h",
            "\(Int((drive.topSpeedKmh * 0.621371).rounded())) mph"
        ]
        return values
            .map { $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) }
            .joined(separator: " ")
    }

    var body: some View {
        GeometryReader { geometry in
            let compactLayout = geometry.size.width < 380 || dynamicTypeSize.isAccessibilitySize
            ZStack {
                SpeedometerStyle.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        header
                        monthSummary(compact: compactLayout)
                        if isSearchPresented {
                            searchField
                                .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .top)), reduceMotion: reduceMotion))
                        }
                        filterControl(compact: compactLayout)

                        if dayGroups.isEmpty {
                            if !normalizedSearchQuery.isEmpty {
                                noMatchesState
                                    .transition(VeluraMotion.transition(.opacity.combined(with: .scale(scale: 0.98)), reduceMotion: reduceMotion))
                            } else if store.drives.isEmpty {
                                emptyState
                                    .transition(VeluraMotion.transition(.opacity.combined(with: .scale(scale: 0.98)), reduceMotion: reduceMotion))
                            } else {
                                filterEmptyState
                                    .transition(VeluraMotion.transition(.opacity.combined(with: .scale(scale: 0.98)), reduceMotion: reduceMotion))
                            }
                        } else {
                            LazyVStack(alignment: .leading, spacing: 18) {
                                ForEach(dayGroups) { group in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(group.title)
                                            .modifier(AdaptiveFont(size: 12, weight: .semibold, design: .rounded))
                                            .tracking(1.3)
                                            .foregroundStyle(SpeedometerStyle.secondary)
                                            .padding(.top, 3)

                                        ForEach(group.drives) { drive in
                                            DriveHistoryRow(
                                                drive: drive,
                                                destination: DriveDetailView(
                                                    drive: drive,
                                                    onDeleteRoute: { store.deleteRoute(for: drive.id) },
                                                    onDelete: { store.delete(drive.id) }
                                                ),
                                                compact: compactLayout
                                            )
                                            .transition(VeluraMotion.transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)), removal: .opacity), reduceMotion: reduceMotion))
                                            .contextMenu {
                                                Button(role: .destructive) {
                                                    withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) { store.delete(drive.id) }
                                                } label: {
                                                    Label("Delete drive", systemImage: "trash")
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, geometry.size.width < 380 ? 14 : 20)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                    .animation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion), value: filter.rawValue)
                    .animation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion), value: store.drives.count)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.visible, for: .tabBar)
        .preferredColorScheme(appearance.preferredColorScheme)
        .navigationDestination(isPresented: $showingInsights) {
            DrivingInsightsView()
        }
        .confirmationDialog("Clear all drive history?", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("Clear all history", role: .destructive) {
                withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) { store.clear() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently deletes all saved drives from this device.")
        }
    }

    private var header: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your drives")
                        .modifier(AdaptiveFont(size: 21, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        historyActions
                    }
                }
            } else {
                HStack {
                    Text("Your drives")
                        .modifier(AdaptiveFont(size: 21, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    historyActions
                }
            }
        }
        .frame(minHeight: 44)
    }

    private var historyActions: some View {
        Menu {
            Button {
                withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                    if isSearchPresented {
                        isSearchPresented = false
                        searchText = ""
                    } else {
                        isSearchPresented = true
                    }
                }
            } label: {
                Label(isSearchPresented ? "Close search" : "Search drives", systemImage: "magnifyingglass")
            }

            Button {
                showingInsights = true
            } label: {
                Label("Driving insights", systemImage: "chart.bar.xaxis")
            }

            if !store.drives.isEmpty {
                Divider()
                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    Label("Clear all history", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .modifier(AdaptiveFont(size: 15, weight: .semibold))
                .foregroundStyle(SpeedometerStyle.foreground)
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel("Search, insights or history actions")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .modifier(AdaptiveFont(size: 15, weight: .medium))
                .foregroundStyle(SpeedometerStyle.secondary)

            TextField("Search date, distance, duration or speed", text: $searchText)
                .modifier(AdaptiveFont(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.foreground)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Search drives by date, distance, duration or top speed")

            if !searchText.isEmpty {
                Button {
                    withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) { searchText = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .modifier(AdaptiveFont(size: 17))
                        .foregroundStyle(SpeedometerStyle.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var noMatchesState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .modifier(AdaptiveFont(size: 27, weight: .light))
                .foregroundStyle(SpeedometerStyle.accent)
            Text("No matching drives")
                .modifier(AdaptiveFont(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(SpeedometerStyle.foreground)
            Text("Try another date, distance, duration or top speed.")
                .modifier(AdaptiveFont(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.secondary)
                .multilineTextAlignment(.center)
            Button {
                withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) { searchText = "" }
            } label: {
                Label("Clear search", systemImage: "xmark.circle")
                    .modifier(AdaptiveFont(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.accent)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.tint(SpeedometerStyle.accent.opacity(0.14)).interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var filterEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .modifier(AdaptiveFont(size: 27, weight: .light))
                .foregroundStyle(SpeedometerStyle.accent)
            Text(filter == .thisWeek ? "No drives this week" : "No drives this month")
                .modifier(AdaptiveFont(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(SpeedometerStyle.foreground)
            Text("Change the time filter to see other saved drives.")
                .modifier(AdaptiveFont(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.secondary)
                .multilineTextAlignment(.center)
            Button {
                withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) { filter = .all }
            } label: {
                Label("Show all drives", systemImage: "clock.arrow.circlepath")
                    .modifier(AdaptiveFont(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.accent)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.tint(SpeedometerStyle.accent.opacity(0.14)).interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func monthSummary(compact: Bool) -> some View {
        let distance = monthDrives.reduce(0) { $0 + $1.distanceKm }
        let duration = monthDrives.reduce(0) { $0 + $1.duration }
        let countMetric = summaryMetric(value: "\(monthDrives.count)", caption: "drives")
        let distanceMetric = summaryMetric(value: "\(String(format: "%.0f", distance * conversion)) \(distanceUnit)", caption: "distance")
        let durationMetric = summaryMetric(value: compactDuration(duration), caption: "total time")

        return VStack(alignment: .leading, spacing: 17) {
            Text("THIS MONTH")
                .modifier(AdaptiveFont(size: 12, weight: .semibold, design: .rounded))
                .tracking(1.25)
                .foregroundStyle(SpeedometerStyle.secondary)

            if compact {
                VStack(alignment: .leading, spacing: 10) {
                    countMetric
                    Rectangle().fill(SpeedometerStyle.foreground.opacity(0.15)).frame(height: 1)
                    distanceMetric
                    Rectangle().fill(SpeedometerStyle.foreground.opacity(0.15)).frame(height: 1)
                    durationMetric
                }
            } else {
                HStack(spacing: 0) {
                    countMetric
                    summaryDivider
                    distanceMetric
                    summaryDivider
                    durationMetric
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 17)
        .background(SpeedometerStyle.foreground.opacity(0.035), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(SpeedometerStyle.foreground.opacity(0.11), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("This month’s driving summary")
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(SpeedometerStyle.foreground.opacity(0.15))
            .frame(width: 1, height: 34)
    }

    private func summaryMetric(value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .modifier(AdaptiveFont(size: 23, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(SpeedometerStyle.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())
            Text(caption)
                .modifier(AdaptiveFont(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func filterControl(compact: Bool) -> some View {
        Group {
            if compact {
                VStack(spacing: 4) {
                    ForEach(HistoryFilter.allCases) { option in
                        filterButton(option)
                    }
                }
            } else {
                HStack(spacing: 3) {
                    ForEach(HistoryFilter.allCases) { option in
                        filterButton(option)
                    }
                }
            }
        }
        .padding(4)
        .background(SpeedometerStyle.foreground.opacity(0.04), in: RoundedRectangle(cornerRadius: compact ? 18 : 28, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: compact ? 18 : 28))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 18 : 28, style: .continuous)
                .stroke(SpeedometerStyle.foreground.opacity(0.09), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drive history date filter")
    }

    private func filterButton(_ option: HistoryFilter) -> some View {
        let isSelected = filter == option
        return Button {
            withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) { filter = option }
        } label: {
            Text(option.rawValue)
                .modifier(AdaptiveFont(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? SpeedometerStyle.foreground : SpeedometerStyle.secondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(SpeedometerStyle.accent.opacity(0.2))
                            .glassEffect(.regular.tint(SpeedometerStyle.accent.opacity(0.35)), in: .capsule)
                            .overlay {
                                Capsule().stroke(SpeedometerStyle.accent.opacity(0.7), lineWidth: 1)
                            }
                            .shadow(color: SpeedometerStyle.accent.opacity(0.3), radius: 8, y: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .modifier(AdaptiveFont(size: 28, weight: .light))
                .foregroundStyle(SpeedometerStyle.accent)
            Text("No drives yet")
                .modifier(AdaptiveFont(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(SpeedometerStyle.foreground)
            Text("Completed drives will appear here.")
                .modifier(AdaptiveFont(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(.top, 3)
    }
}

private struct DriveHistoryRow: View {
    @ObservedObject private var appearance = AppAppearance.shared
    @AppStorage("speedometer.usesMiles") private var usesMiles = false
    let drive: DriveRecord
    let destination: DriveDetailView
    let compact: Bool

    private var displayedDistance: Double { usesMiles ? drive.distanceKm * 0.621371 : drive.distanceKm }
    private var displayedTopSpeed: Double { usesMiles ? drive.topSpeedKmh * 0.621371 : drive.topSpeedKmh }
    private var distanceUnit: String { usesMiles ? "mi" : "km" }
    private var speedUnit: String { usesMiles ? "mph" : "km/h" }

    var body: some View {
        NavigationLink(destination: destination) {
            Group {
                if compact {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 12) {
                            routePreview
                            VStack(alignment: .leading, spacing: 5) {
                                driveTime
                                driveDistance
                            }
                            Spacer(minLength: 0)
                        }
                        HStack {
                            Text("Top speed")
                                .modifier(AdaptiveFont(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(SpeedometerStyle.secondary)
                            Spacer()
                            topSpeed
                        }
                    }
                } else {
                    HStack(spacing: 13) {
                        routePreview
                        VStack(alignment: .leading, spacing: 5) {
                            driveTime
                            driveDistance
                        }
                        Spacer(minLength: 5)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Top")
                                .modifier(AdaptiveFont(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(SpeedometerStyle.secondary)
                            topSpeed
                        }
                        Image(systemName: "chevron.right")
                            .modifier(AdaptiveFont(size: 12, weight: .semibold))
                            .foregroundStyle(SpeedometerStyle.secondary.opacity(0.8))
                            .padding(.leading, 1)
                    }
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, compact ? 11 : 7)
            .background(SpeedometerStyle.foreground.opacity(0.035), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(SpeedometerStyle.accent.opacity(0.16), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Drive at \(drive.date.formatted(date: .omitted, time: .shortened)), \(String(format: "%.1f", displayedDistance)) \(usesMiles ? "miles" : "kilometres"), top speed \(Int(displayedTopSpeed.rounded())) \(usesMiles ? "miles per hour" : "kilometres per hour")")
        .accessibilityHint("Opens drive details. Touch and hold to delete.")
    }

    private var routePreview: some View {
        DriveRoutePreview(routeCoordinates: drive.routeCoordinates)
            .frame(width: 68, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(SpeedometerStyle.foreground.opacity(0.08), lineWidth: 1)
            }
    }

    private var driveTime: some View {
        Text(drive.date.formatted(date: .omitted, time: .shortened))
            .modifier(AdaptiveFont(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(SpeedometerStyle.foreground)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var driveDistance: some View {
        Text("\(String(format: "%.1f", displayedDistance)) \(distanceUnit) · \(rowDuration(drive.duration))")
            .modifier(AdaptiveFont(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(SpeedometerStyle.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var topSpeed: some View {
        Text("\(Int(displayedTopSpeed.rounded())) \(speedUnit)")
            .modifier(AdaptiveFont(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(SpeedometerStyle.foreground)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DriveRoutePreview: View {
    @ObservedObject private var appearance = AppAppearance.shared
    let routeCoordinates: [DriveRoutePoint]

    private var previewCoordinates: [DriveRoutePoint] {
        let validCoordinates = routeCoordinates.filter {
            $0.latitude.isFinite && $0.longitude.isFinite
                && (-90.0...90.0).contains($0.latitude)
                && (-180.0...180.0).contains($0.longitude)
        }
        let maximumPointCount = 100
        guard validCoordinates.count > maximumPointCount else { return validCoordinates }

        let interval = Double(validCoordinates.count - 1) / Double(maximumPointCount - 1)
        return (0..<maximumPointCount).map { index in
            validCoordinates[Int((Double(index) * interval).rounded())]
        }
    }

    private var hasRenderableRoute: Bool {
        guard let first = previewCoordinates.first, previewCoordinates.count > 1 else { return false }
        return previewCoordinates.dropFirst().contains {
            $0.latitude != first.latitude || $0.longitude != first.longitude
        }
    }

    var body: some View {
        Group {
            if hasRenderableRoute {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(SpeedometerStyle.background))
                    let points = previewPoints(in: size)
                    guard let start = points.first, let finish = points.last else { return }

                    var route = Path()
                    route.move(to: start)
                    for point in points.dropFirst() {
                        route.addLine(to: point)
                    }
                    context.stroke(route, with: .color(SpeedometerStyle.accent.opacity(0.26)), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    context.stroke(route, with: .color(SpeedometerStyle.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    let startMarker = CGRect(x: start.x - 4, y: start.y - 4, width: 8, height: 8)
                    let finishMarker = CGRect(x: finish.x - 4, y: finish.y - 4, width: 8, height: 8)
                    context.fill(Path(ellipseIn: startMarker), with: .color(SpeedometerStyle.background))
                    context.stroke(Path(ellipseIn: startMarker), with: .color(SpeedometerStyle.mint), lineWidth: 1.8)
                    context.fill(Path(ellipseIn: finishMarker), with: .color(SpeedometerStyle.accent))
                    context.stroke(Path(ellipseIn: finishMarker), with: .color(SpeedometerStyle.background), lineWidth: 1.4)
                }
            } else {
                VStack(spacing: 2) {
                    Image(systemName: "map")
                        .modifier(AdaptiveFont(size: 17, weight: .light))
                    Text("No route")
                        .modifier(AdaptiveFont(size: 8, weight: .medium, design: .rounded))
                }
                .foregroundStyle(SpeedometerStyle.secondary.opacity(0.82))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SpeedometerStyle.background)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }

    private func previewPoints(in size: CGSize) -> [CGPoint] {
        let coordinates = previewCoordinates
        guard coordinates.count > 1 else { return [] }

        let meanLatitude = coordinates.reduce(0.0) { $0 + $1.latitude } / Double(coordinates.count) * Double.pi / 180
        let longitudeScale = cos(meanLatitude)
        let projected = coordinates.map { (x: $0.longitude * longitudeScale, y: $0.latitude) }
        guard let minX = projected.map({ $0.x }).min(),
              let maxX = projected.map({ $0.x }).max(),
              let minY = projected.map({ $0.y }).min(),
              let maxY = projected.map({ $0.y }).max() else { return [] }

        let spanX = maxX - minX
        let spanY = maxY - minY
        guard spanX > 0 || spanY > 0 else { return [] }

        let inset: CGFloat = 7
        let availableWidth = max(1, size.width - inset * 2)
        let availableHeight = max(1, size.height - inset * 2)
        return projected.map { point in
            let xFraction = spanX > 0 ? (point.x - minX) / spanX : 0.5
            let yFraction = spanY > 0 ? (maxY - point.y) / spanY : 0.5
            return CGPoint(
                x: inset + CGFloat(xFraction) * availableWidth,
                y: inset + CGFloat(yFraction) * availableHeight
            )
        }
    }
}

private struct DriveDetailView: View {
    @ObservedObject private var appearance = AppAppearance.shared
    @AppStorage("speedometer.usesMiles") private var usesMiles = false
    let drive: DriveRecord
    let onDeleteRoute: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingDeleteConfirmation = false
    @State private var routeCoordinates: [DriveRoutePoint]

    init(drive: DriveRecord, onDeleteRoute: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.drive = drive
        self.onDeleteRoute = onDeleteRoute
        self.onDelete = onDelete
        _routeCoordinates = State(initialValue: drive.routeCoordinates)
    }

    private var displayedDistance: Double { usesMiles ? drive.distanceKm * 0.621371 : drive.distanceKm }
    private var displayedTopSpeed: Double { usesMiles ? drive.topSpeedKmh * 0.621371 : drive.topSpeedKmh }
    private var distanceUnit: String { usesMiles ? "mi" : "km" }
    private var speedUnit: String { usesMiles ? "mph" : "km/h" }

    private var driveWithCurrentRoute: DriveRecord {
        var updatedDrive = drive
        updatedDrive.routeCoordinates = routeCoordinates
        return updatedDrive
    }

    var body: some View {
        ZStack {
            SpeedometerStyle.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left")
                                .modifier(AdaptiveFont(size: 16, weight: .semibold))
                                .foregroundStyle(SpeedometerStyle.foreground)
                                .frame(width: 44, height: 44)
                                .glassEffect(.regular.interactive(), in: .circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back to drives")
                        Text("Drive details")
                            .modifier(AdaptiveFont(size: 19, weight: .semibold, design: .rounded))
                            .foregroundStyle(SpeedometerStyle.foreground)
                        Spacer()
                    }

                    VStack(spacing: 7) {
                        Image(systemName: "calendar")
                            .modifier(AdaptiveFont(size: 20, weight: .medium))
                            .foregroundStyle(SpeedometerStyle.accent)
                        Text(drive.date.formatted(date: .complete, time: .shortened))
                            .modifier(AdaptiveFont(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(SpeedometerStyle.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)

                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(spacing: 12) {
                                detailMetric(title: "DISTANCE", value: String(format: "%.2f %@", displayedDistance, distanceUnit))
                                Rectangle().fill(SpeedometerStyle.foreground.opacity(0.12)).frame(height: 1)
                                detailMetric(title: "DURATION", value: detailedDuration(drive.duration))
                                Rectangle().fill(SpeedometerStyle.foreground.opacity(0.12)).frame(height: 1)
                                detailMetric(title: "TOP SPEED", value: "\(Int(displayedTopSpeed.rounded())) \(speedUnit)")
                            }
                        } else {
                            HStack(spacing: 0) {
                                detailMetric(title: "DISTANCE", value: String(format: "%.2f %@", displayedDistance, distanceUnit))
                                detailDivider
                                detailMetric(title: "DURATION", value: detailedDuration(drive.duration))
                                detailDivider
                                detailMetric(title: "TOP SPEED", value: "\(Int(displayedTopSpeed.rounded())) \(speedUnit)")
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 17)
                    .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))

                    NavigationLink {
                        DriveRouteView(drive: driveWithCurrentRoute) {
                            onDeleteRoute()
                            routeCoordinates.removeAll()
                        }
                    } label: {
                        Label("View route", systemImage: "map.fill")
                            .modifier(AdaptiveFont(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(SpeedometerStyle.accent)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                            .glassEffect(.regular.tint(SpeedometerStyle.accent.opacity(0.15)), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the recorded route, or an explanation if no route was saved")

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete drive", systemImage: "trash")
                            .modifier(AdaptiveFont(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.red.opacity(0.9))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                            .glassEffect(.regular, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Delete this drive?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                        Button("Delete drive", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) { }
                    } message: {
                        Text("This drive will be permanently removed from your history.")
                    }
                }
                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 14 : 22)
                .padding(.vertical, 20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.visible, for: .tabBar)
        .preferredColorScheme(appearance.preferredColorScheme)
    }

    private var detailDivider: some View {
        Rectangle()
            .fill(SpeedometerStyle.foreground.opacity(0.12))
            .frame(width: 1, height: 38)
    }

    private func detailMetric(title: String, value: String) -> some View {
        VStack(spacing: 7) {
            Text(title)
                .modifier(AdaptiveFont(size: 8, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(SpeedometerStyle.secondary)
            Text(value)
                .modifier(AdaptiveFont(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(SpeedometerStyle.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private func rowDuration(_ duration: TimeInterval) -> String {
    let minutes = max(0, Int(duration / 60))
    return minutes == 1 ? "1 min" : "\(minutes) min"
}

private func compactDuration(_ duration: TimeInterval) -> String {
    let minutes = max(0, Int(duration / 60))
    let hours = minutes / 60
    let remainder = minutes % 60
    if hours > 0 { return "\(hours)h \(remainder)m" }
    return "\(minutes)m"
}

private func detailedDuration(_ duration: TimeInterval) -> String {
    let totalSeconds = max(0, Int(duration))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
    return String(format: "%02d:%02d", minutes, seconds)
}

#Preview {
    NavigationStack {
        DriveHistoryView()
    }
}
