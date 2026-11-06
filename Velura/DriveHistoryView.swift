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
    @StateObject private var store = DriveHistoryStore.shared
    @State private var filter: HistoryFilter = .all
    @State private var searchText = ""
    @State private var selectedDrive: DriveRecord?
    @State private var showingClearConfirmation = false
    @State private var isSearchPresented = false
    @State private var showingInsights = false

    private let onBack: () -> Void

    init(onBack: @escaping () -> Void = {}) {
        self.onBack = onBack
    }

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
            rowDuration(drive.duration),
            detailedDuration(drive.duration),
            "\(Int(drive.topSpeedKmh.rounded())) km/h"
        ]
        return values
            .map { $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) }
            .joined(separator: " ")
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SpeedometerStyle.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        header
                        monthSummary
                        if isSearchPresented {
                            searchField
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        filterControl

                        if dayGroups.isEmpty {
                            if !normalizedSearchQuery.isEmpty {
                                noMatchesState
                            } else if store.drives.isEmpty {
                                emptyState
                            } else {
                                filterEmptyState
                            }
                        } else {
                            LazyVStack(alignment: .leading, spacing: 18) {
                                ForEach(dayGroups) { group in
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(group.title)
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                            .tracking(1.4)
                                            .foregroundStyle(SpeedometerStyle.secondary)
                                            .padding(.top, 3)

                                        ForEach(group.drives) { drive in
                                            DriveHistoryRow(drive: drive) {
                                                selectedDrive = drive
                                            }
                                            .contextMenu {
                                                Button(role: .destructive) {
                                                    withAnimation(.snappy) { store.delete(drive.id) }
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
                    .padding(.horizontal, geometry.size.width < 380 ? 16 : 20)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(.dark)
        .navigationDestination(isPresented: $showingInsights) {
            DrivingInsightsView()
        }
        .sheet(item: $selectedDrive) { drive in
            DriveDetailView(drive: drive, onDeleteRoute: {
                store.deleteRoute(for: drive.id)
            }) {
                store.delete(drive.id)
                selectedDrive = nil
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(SpeedometerStyle.background)
        }
        .confirmationDialog("Clear all drive history?", isPresented: $showingClearConfirmation, titleVisibility: .visible) {
            Button("Clear all history", role: .destructive) {
                withAnimation(.snappy) { store.clear() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently deletes all saved drives from this device.")
        }
    }

    private var header: some View {
        ZStack {
            Text("Your drives")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to speedometer")

                Spacer()

                Menu {
                    Button {
                        withAnimation(.snappy(duration: 0.28)) {
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .accessibilityLabel("Search, insights or history actions")
            }
        }
        .frame(height: 48)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SpeedometerStyle.secondary)

            TextField("Search date, distance, duration or speed", text: $searchText)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Search drives by date, distance, duration or top speed")

            if !searchText.isEmpty {
                Button {
                    withAnimation(.snappy) { searchText = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(SpeedometerStyle.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private var noMatchesState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(SpeedometerStyle.accent)
            Text("No matching drives")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("Try another date, distance, duration or top speed.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.secondary)
                .multilineTextAlignment(.center)
            Button {
                withAnimation(.snappy) { searchText = "" }
            } label: {
                Label("Clear search", systemImage: "xmark.circle")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
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
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var filterEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(SpeedometerStyle.accent)
            Text(filter == .thisWeek ? "No drives this week" : "No drives this month")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("Change the time filter to see other saved drives.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.secondary)
                .multilineTextAlignment(.center)
            Button {
                withAnimation(.snappy) { filter = .all }
            } label: {
                Label("Show all drives", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
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
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var monthSummary: some View {
        let distance = monthDrives.reduce(0) { $0 + $1.distanceKm }
        let duration = monthDrives.reduce(0) { $0 + $1.duration }

        return VStack(alignment: .leading, spacing: 16) {
            Text("THIS MONTH")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.35)
                .foregroundStyle(SpeedometerStyle.secondary)

            HStack(spacing: 0) {
                summaryMetric(value: "\(monthDrives.count)", caption: "DRIVES")
                summaryDivider
                summaryMetric(value: String(format: "%.1f", distance), caption: "KM")
                summaryDivider
                summaryMetric(value: compactDuration(duration), caption: "TOTAL TIME")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 17)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("This month’s driving summary")
    }

    private var summaryDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.15))
            .frame(width: 1, height: 42)
    }

    private func summaryMetric(value: String, caption: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 23, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .contentTransition(.numericText())
            Text(caption)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .tracking(0.65)
                .foregroundStyle(SpeedometerStyle.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var filterControl: some View {
        HStack(spacing: 3) {
            ForEach(HistoryFilter.allCases) { option in
                let isSelected = filter == option
                Button {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { filter = option }
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? AppAppearance.shared.theme.accentForeground : SpeedometerStyle.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(SpeedometerStyle.accent.opacity(0.9))
                                    .overlay {
                                        Capsule().stroke(.white.opacity(0.2), lineWidth: 1)
                                    }
                                    .shadow(color: SpeedometerStyle.accent.opacity(0.2), radius: 7, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.white.opacity(0.045), in: Capsule())
        .glassEffect(.regular, in: .capsule)
        .overlay {
            Capsule().stroke(.white.opacity(0.09), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drive history date filter")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(SpeedometerStyle.accent)
            Text("No drives yet")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("Completed drives will appear here.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(.top, 3)
    }
}

private struct DriveHistoryRow: View {
    @ObservedObject private var appearance = AppAppearance.shared
    let drive: DriveRecord
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                DriveRouteGlyph()
                    .frame(width: 62, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 5) {
                    Text(drive.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("\(String(format: "%.1f", drive.distanceKm)) km · \(rowDuration(drive.duration))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 5)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("TOP SPEED")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(0.65)
                        .foregroundStyle(SpeedometerStyle.secondary)
                    Text("\(Int(drive.topSpeedKmh.rounded())) km/h")
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SpeedometerStyle.secondary.opacity(0.8))
                    .padding(.leading, 1)
            }
            .padding(11)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Drive at \(drive.date.formatted(date: .omitted, time: .shortened)), \(String(format: "%.1f", drive.distanceKm)) kilometres, top speed \(Int(drive.topSpeedKmh.rounded())) kilometres per hour")
        .accessibilityHint("Opens drive details. Touch and hold to delete.")
    }
}

private struct DriveRouteGlyph: View {
    @ObservedObject private var appearance = AppAppearance.shared

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            context.fill(Path(bounds), with: .color(SpeedometerStyle.background))

            var street = Path()
            street.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.24))
            street.addCurve(to: CGPoint(x: size.width * 0.89, y: size.height * 0.16), control1: CGPoint(x: size.width * 0.34, y: size.height * 0.04), control2: CGPoint(x: size.width * 0.56, y: size.height * 0.38))
            street.move(to: CGPoint(x: size.width * 0.13, y: size.height * 0.93))
            street.addLine(to: CGPoint(x: size.width * 0.35, y: size.height * 0.63))
            street.addLine(to: CGPoint(x: size.width * 0.83, y: size.height * 0.72))
            context.stroke(street, with: .color(.white.opacity(0.065)), style: StrokeStyle(lineWidth: 1, lineCap: .round))

            var route = Path()
            route.move(to: CGPoint(x: size.width * 0.16, y: size.height * 0.84))
            route.addLine(to: CGPoint(x: size.width * 0.36, y: size.height * 0.66))
            route.addLine(to: CGPoint(x: size.width * 0.53, y: size.height * 0.69))
            route.addLine(to: CGPoint(x: size.width * 0.72, y: size.height * 0.5))
            route.addLine(to: CGPoint(x: size.width * 0.86, y: size.height * 0.2))
            context.stroke(route, with: .color(SpeedometerStyle.accent), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            for point in [CGPoint(x: size.width * 0.16, y: size.height * 0.84), CGPoint(x: size.width * 0.86, y: size.height * 0.2)] {
                let marker = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: marker), with: .color(SpeedometerStyle.background))
                context.stroke(Path(ellipseIn: marker), with: .color(SpeedometerStyle.accent), lineWidth: 1.8)
            }
        }
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct DriveDetailView: View {
    @ObservedObject private var appearance = AppAppearance.shared
    let drive: DriveRecord
    let onDeleteRoute: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false
    @State private var showingRoute = false
    @State private var routeCoordinates: [DriveRoutePoint]

    init(drive: DriveRecord, onDeleteRoute: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.drive = drive
        self.onDeleteRoute = onDeleteRoute
        self.onDelete = onDelete
        _routeCoordinates = State(initialValue: drive.routeCoordinates)
    }

    private var driveWithCurrentRoute: DriveRecord {
        var updatedDrive = drive
        updatedDrive.routeCoordinates = routeCoordinates
        return updatedDrive
    }

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Text("Drive details")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SpeedometerStyle.secondary)
                        .frame(width: 32, height: 32)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close drive details")
            }

            VStack(spacing: 7) {
                Image(systemName: "calendar")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(SpeedometerStyle.accent)
                Text(drive.date.formatted(date: .complete, time: .shortened))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 0) {
                detailMetric(title: "DISTANCE", value: String(format: "%.2f km", drive.distanceKm))
                detailDivider
                detailMetric(title: "DURATION", value: detailedDuration(drive.duration))
                detailDivider
                detailMetric(title: "TOP SPEED", value: "\(Int(drive.topSpeedKmh.rounded())) km/h")
            }
            .padding(.vertical, 17)
            .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .glassEffect(.regular, in: .rect(cornerRadius: 22))

            Button {
                showingRoute = true
            } label: {
                Label("View route", systemImage: "map.fill")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .glassEffect(.regular.tint(SpeedometerStyle.accent.opacity(0.15)), in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the recorded route, or an explanation if no route was saved")

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("Delete drive", systemImage: "trash")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .glassEffect(.regular, in: .capsule)
            }
            .buttonStyle(.plain)
            .confirmationDialog("Delete this drive?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete drive", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This drive will be permanently removed from your history.")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .fullScreenCover(isPresented: $showingRoute) {
            DriveRouteView(drive: driveWithCurrentRoute) {
                onDeleteRoute()
                routeCoordinates.removeAll()
            }
            .preferredColorScheme(.dark)
        }
    }

    private var detailDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(width: 1, height: 38)
    }

    private func detailMetric(title: String, value: String) -> some View {
        VStack(spacing: 7) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(SpeedometerStyle.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
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
