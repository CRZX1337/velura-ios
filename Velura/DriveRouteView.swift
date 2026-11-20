import MapKit
import SwiftUI
import UIKit

struct DriveRouteView: View {
    let drive: DriveRecord
    let onDeleteRoute: () -> Void
    let onBack: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var routeHeaderGlassNamespace
    @ObservedObject private var appearance = AppAppearance.shared
    @AppStorage("speedometer.usesMiles") private var usesMiles = false
    @State private var routeCoordinates: [DriveRoutePoint]
    @State private var showsRecordingGaps = true
    @State private var showsSpeedHeatmap = false
    @State private var highlightedSpeedBand: RouteSpeedBand?
    @State private var heatmapSegments: [RouteHeatmapSegment] = []
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showingDeleteConfirmation = false
    @State private var isPreparingShare = false
    @State private var shareContent: RouteShareContent?
    @State private var showingShareError = false
    @State private var shareErrorMessage = ""

    init(drive: DriveRecord, onDeleteRoute: @escaping () -> Void, onBack: @escaping () -> Void) {
        self.drive = drive
        self.onDeleteRoute = onDeleteRoute
        self.onBack = onBack
        _routeCoordinates = State(initialValue: drive.routeCoordinates)
        let builtSegments = RouteSpeedHeatmapBuilder.buildSegments(from: drive.routeCoordinates)
        _heatmapSegments = State(initialValue: builtSegments)
        _showsSpeedHeatmap = State(initialValue: !builtSegments.isEmpty)
    }

    private var hasSpeedHeatmapData: Bool {
        !heatmapSegments.isEmpty
    }

    private var elevationSummary: ElevationSummary? {
        DrivingInsightsCalculator.elevationProfile(for: drive)
    }

    private var coordinates: [CLLocationCoordinate2D] {
        routeCoordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    private var routePointSegments: [[DriveRoutePoint]] {
        var segments: [[DriveRoutePoint]] = []
        var currentSegmentIndex: Int?
        for point in routeCoordinates {
            if currentSegmentIndex != point.segmentIndex {
                segments.append([])
                currentSegmentIndex = point.segmentIndex
            }
            segments[segments.count - 1].append(point)
        }
        return segments
    }

    private var routeSegments: [[CLLocationCoordinate2D]] {
        routePointSegments.map { segment in
            segment.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        }
    }

    private var displayedDistance: Double {
        usesMiles ? drive.distanceKm * 0.621371 : drive.distanceKm
    }

    private var displayedTopSpeed: Double {
        usesMiles ? drive.topSpeedKmh * 0.621371 : drive.topSpeedKmh
    }

    private var distanceUnit: String { usesMiles ? "mi" : "km" }
    private var speedUnit: String { usesMiles ? "mph" : "km/h" }

    private var dateChipText: String {
        let day = Calendar.current.isDateInToday(drive.date)
            ? "TODAY"
            : drive.date.formatted(date: .abbreviated, time: .omitted).uppercased()
        return "\(day) · \(drive.date.formatted(date: .omitted, time: .shortened))"
    }

    private var routeRegion: MKCoordinateRegion {
        let latitudes = routeCoordinates.map(\.latitude)
        let longitudes = routeCoordinates.map(\.longitude)
        let minimumLatitude = latitudes.min() ?? 0
        let maximumLatitude = latitudes.max() ?? 0
        let minimumLongitude = longitudes.min() ?? 0
        let maximumLongitude = longitudes.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minimumLatitude + maximumLatitude) / 2,
            longitude: (minimumLongitude + maximumLongitude) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maximumLatitude - minimumLatitude) * 1.6, 0.004),
            longitudeDelta: max((maximumLongitude - minimumLongitude) * 1.6, 0.004)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SpeedometerStyle.background.ignoresSafeArea()

                if routeCoordinates.count >= 2 {
                    routeMap
                        .transition(VeluraMotion.transition(.opacity, reduceMotion: reduceMotion))
                } else {
                    emptyMapState
                        .transition(VeluraMotion.transition(.opacity, reduceMotion: reduceMotion))
                }

                VStack(spacing: 0) {
                    header

                    if routeCoordinates.count >= 2 {
                        HStack(spacing: 8) {
                            Text(dateChipText)
                                .modifier(AdaptiveFont(size: 12, weight: .semibold, design: .rounded))
                                .tracking(1.1)
                                .foregroundStyle(SpeedometerStyle.foreground.opacity(0.88))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .veluraGlassCapsule()

                            if hasSpeedHeatmapData {
                                Button {
                                    withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                                        showsSpeedHeatmap.toggle()
                                        if !showsSpeedHeatmap {
                                            highlightedSpeedBand = nil
                                        }
                                    }
                                } label: {
                                    Label(
                                        showsSpeedHeatmap ? "Heatmap" : "Standard",
                                        systemImage: showsSpeedHeatmap ? "flame.fill" : "point.topleft.down.to.point.bottomright.curvepath"
                                    )
                                    .modifier(AdaptiveFont(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(showsSpeedHeatmap ? SpeedometerStyle.accentForeground : SpeedometerStyle.foreground)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 9)
                                    .background {
                                        if showsSpeedHeatmap {
                                            Capsule().fill(SpeedometerStyle.accent)
                                        }
                                    }
                                    .veluraGlassCapsule(tint: showsSpeedHeatmap ? nil : .clear, interactive: true)
                                }
                                .buttonStyle(VeluraGlassPressButtonStyle())
                                .accessibilityLabel(showsSpeedHeatmap ? "Switch to standard route color" : "Switch to speed heatmap")
                            }
                        }
                        .padding(.top, 8)

                        if showsSpeedHeatmap && hasSpeedHeatmapData {
                            speedHeatmapLegend
                                .padding(.top, 8)
                                .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .top)), reduceMotion: reduceMotion))
                        }
                    }

                    Spacer(minLength: geometry.size.height > 600 ? 14 : 4)

                    Group {
                        if dynamicTypeSize.isAccessibilitySize || geometry.size.height < 500 {
                            ScrollView(showsIndicators: false) {
                                summaryCard
                            }
                            .frame(maxHeight: min(geometry.size.height * 0.55, max(100, geometry.size.height - 120)))
                        } else {
                            summaryCard
                        }
                    }
                }
                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 14 : 22)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .zIndex(1)
            }
        }
        .preferredColorScheme(appearance.preferredColorScheme)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.visible, for: .tabBar)
        .animation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion), value: routeCoordinates.count >= 2)
        .confirmationDialog("Delete this route?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete route", role: .destructive) {
                onDeleteRoute()
                withAnimation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion)) {
                    routeCoordinates.removeAll()
                    heatmapSegments.removeAll()
                    showsSpeedHeatmap = false
                    highlightedSpeedBand = nil
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The route will be removed from this device. Drive statistics will be kept.")
        }
        .sheet(item: $shareContent) { content in
            RouteActivityView(activityItems: content.items)
        }
        .sensoryFeedback(.selection, trigger: showsSpeedHeatmap)
        .sensoryFeedback(.selection, trigger: highlightedSpeedBand)
        .alert("Unable to share route", isPresented: $showingShareError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(shareErrorMessage)
        }
    }

    private var routeMap: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
            if showsSpeedHeatmap && hasSpeedHeatmapData {
                ForEach(heatmapSegments) { segment in
                    let isDimmed = highlightedSpeedBand != nil && highlightedSpeedBand != segment.band
                    MapPolyline(coordinates: segment.coordinates)
                        .stroke(
                            segment.band.color.opacity(isDimmed ? 0.22 : 0.96),
                            lineWidth: isDimmed ? 3.5 : 5.5
                        )
                }
            } else {
                ForEach(routeSegments.indices, id: \.self) { index in
                    let segment = routeSegments[index]
                    if segment.count > 1 {
                        MapPolyline(coordinates: segment)
                            .stroke(SpeedometerStyle.accent, lineWidth: 5)
                    }
                }
            }

            if let start = coordinates.first {
                Annotation("Start", coordinate: start, anchor: .center) {
                    RouteMapMarker(color: SpeedometerStyle.mint)
                }
            }

            if let finish = coordinates.last {
                Annotation("Finish", coordinate: finish, anchor: .center) {
                    RouteMapMarker(color: SpeedometerStyle.warning)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .ignoresSafeArea()
        .onAppear {
            cameraPosition = .region(routeRegion)
        }
        .accessibilityLabel("Recorded drive route map")
    }

    private var speedHeatmapLegend: some View {
        HStack(spacing: 6) {
            ForEach(RouteSpeedBand.allCases) { band in
                let isSelected = highlightedSpeedBand == band
                Button {
                    withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                        highlightedSpeedBand = isSelected ? nil : band
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(band.color)
                            .frame(width: 8, height: 8)
                        Text(band.rangeLabel(usesMiles: usesMiles))
                            .modifier(AdaptiveFont(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(isSelected ? SpeedometerStyle.foreground : SpeedometerStyle.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(isSelected ? band.color.opacity(0.22) : .clear, in: Capsule())
                    .overlay {
                        if isSelected {
                            Capsule().stroke(band.color.opacity(0.75), lineWidth: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(band.title), \(band.rangeLabel(usesMiles: usesMiles))")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .veluraGlassCapsule()
    }

    private var emptyMapState: some View {
        ZStack {
            VeluraAmbientBackdrop(intensity: 0.14)
            Circle()
                .stroke(SpeedometerStyle.foreground.opacity(0.035), lineWidth: 1)
                .frame(width: 300, height: 300)
            Circle()
                .stroke(SpeedometerStyle.foreground.opacity(0.025), lineWidth: 1)
                .frame(width: 430, height: 430)

            VStack(spacing: 11) {
                Image(systemName: "map")
                    .modifier(AdaptiveFont(size: 28, weight: .light))
                    .foregroundStyle(SpeedometerStyle.accent)
                Text("No route recorded")
                    .modifier(AdaptiveFont(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.foreground)
                Text("A route will appear here when GPS locations were recorded during this drive.")
                    .modifier(AdaptiveFont(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 270)
            }
            .padding(24)
            .veluraGlassCard(cornerRadius: 24)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var header: some View {
        GlassEffectContainer(spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        backButton
                        Spacer()
                        headerShareButton
                    }
                    Text("Drive route")
                        .modifier(AdaptiveFont(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack {
                    backButton
                    Spacer()
                    Text("Drive route")
                        .modifier(AdaptiveFont(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .veluraGlassCapsule()
                        .glassEffectID("route-header-title", in: routeHeaderGlassNamespace)
                    Spacer()
                    headerShareButton
                }
            }
        }
    }

    private var backButton: some View {
        Button {
            dismiss()
            onBack()
        } label: {
            Image(systemName: "chevron.left")
                .modifier(AdaptiveFont(size: 16, weight: .semibold))
                .foregroundStyle(SpeedometerStyle.foreground)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .veluraGlassCircle(interactive: true)
                .glassEffectID("route-header-back", in: routeHeaderGlassNamespace)
        }
        .buttonStyle(VeluraGlassPressButtonStyle())
        .accessibilityLabel("Back to drive details")
    }

    @ViewBuilder
    private var headerShareButton: some View {
        if routeCoordinates.count >= 2 {
            Menu {
                Button {
                    Task { await prepareShare() }
                } label: {
                    Label("Share route image", systemImage: "photo")
                }

                Button {
                    exportGPX()
                } label: {
                    Label("Export GPX file", systemImage: "doc.text")
                }
            } label: {
                Group {
                    if isPreparingShare {
                        ProgressView()
                            .tint(SpeedometerStyle.foreground)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .modifier(AdaptiveFont(size: 16, weight: .semibold))
                            .foregroundStyle(SpeedometerStyle.foreground)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .veluraGlassCircle(interactive: true)
                .glassEffectID("route-header-share", in: routeHeaderGlassNamespace)
            }
            .disabled(isPreparingShare)
            .accessibilityLabel("Share or export drive route")
            .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: isPreparingShare)
        } else {
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
    }

    private func exportGPX() {
        var driveSnapshot = drive
        driveSnapshot.routeCoordinates = routeCoordinates
        do {
            let fileURL = try GPXExporter.writeTemporaryGPXFile(for: driveSnapshot)
            shareContent = RouteShareContent(items: [fileURL])
        } catch {
            shareErrorMessage = error.localizedDescription
            showingShareError = true
        }
    }

    @MainActor
    private func prepareShare() async {
        guard routeCoordinates.count >= 2 else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }

        do {
            let mapImage = try await makeRouteImage()
            let date = drive.date.formatted(date: .long, time: .shortened)
            var messageLines = [
                "Velura drive · \(date)",
                "Distance: \(String(format: "%.1f", displayedDistance)) \(distanceUnit)",
                "Duration: \(routeDuration(drive.duration))",
                "Top speed: \(Int(displayedTopSpeed.rounded())) \(speedUnit)"
            ]
            if !drive.interruptionGaps.isEmpty {
                messageLines.append("Tracking gaps: \(drive.interruptionGaps.count) · unrecorded sections are not drawn or estimated.")
            }
            shareContent = RouteShareContent(items: [messageLines.joined(separator: "\n"), mapImage])
        } catch {
            shareErrorMessage = "The route map couldn't be prepared. Please try again."
            showingShareError = true
        }
    }

    private func makeRouteImage() async throws -> UIImage {
        let options = MKMapSnapshotter.Options()
        options.region = routeRegion
        options.size = CGSize(width: 1200, height: 900)
        options.mapType = .standard
        options.pointOfInterestFilter = .excludingAll

        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot: MKMapSnapshotter.Snapshot = try await withCheckedThrowingContinuation { continuation in
            snapshotter.start { snapshot, error in
                if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: error ?? RouteShareError.snapshotUnavailable)
                }
            }
        }

        let routePoints = coordinates.map { snapshot.point(for: $0) }
        let routePointSegments = self.routePointSegments.map { segment in
            segment.map { point in
                snapshot.point(for: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
            }
        }
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)

            let routePath = UIBezierPath()
            routePath.lineWidth = 7
            routePath.lineCapStyle = .round
            routePath.lineJoinStyle = .round
            for segment in routePointSegments where !segment.isEmpty {
                routePath.move(to: segment[0])
                for point in segment.dropFirst() {
                    routePath.addLine(to: point)
                }
            }
            UIColor(SpeedometerStyle.accent).setStroke()
            routePath.stroke()

            drawRouteMarker(at: routePoints[0], color: SpeedometerStyle.mint)
            drawRouteMarker(at: routePoints[routePoints.count - 1], color: SpeedometerStyle.warning)
        }
    }

    private func drawRouteMarker(at point: CGPoint, color: Color) {
        let marker = UIBezierPath(ovalIn: CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20))
        UIColor(color).setFill()
        marker.fill()

        let center = UIBezierPath(ovalIn: CGRect(x: point.x - 4.5, y: point.y - 4.5, width: 9, height: 9))
        UIColor(AppAppearance.shared.theme.foreground(on: color)).setFill()
        center.fill()
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(String(format: "%.1f", displayedDistance)) \(distanceUnit)")
                    .modifier(AdaptiveFont(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(SpeedometerStyle.foreground)
                    .contentTransition(.numericText())
                    .fixedSize(horizontal: false, vertical: true)
                Text("DISTANCE")
                    .modifier(AdaptiveFont(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(SpeedometerStyle.secondary)
            }

            Rectangle()
                .fill(SpeedometerStyle.foreground.opacity(0.11))
                .frame(height: 1)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        summaryMetric(title: "TOP SPEED", value: "\(Int(displayedTopSpeed.rounded())) \(speedUnit)")
                        Rectangle()
                            .fill(SpeedometerStyle.foreground.opacity(0.12))
                            .frame(height: 1)
                        summaryMetric(title: "DURATION", value: routeDuration(drive.duration))
                    }
                } else {
                    HStack(spacing: 0) {
                        summaryMetric(title: "TOP SPEED", value: "\(Int(displayedTopSpeed.rounded())) \(speedUnit)")
                        Rectangle()
                            .fill(SpeedometerStyle.foreground.opacity(0.12))
                            .frame(width: 1, height: 38)
                        summaryMetric(title: "DURATION", value: routeDuration(drive.duration))
                    }
                }
            }

            if let elevation = elevationSummary {
                elevationProfileCard(elevation)
            }

            if !drive.interruptionGaps.isEmpty {
                interruptionGapNotice
            }

            if routeCoordinates.count >= 2 {
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete route", systemImage: "trash")
                        .modifier(AdaptiveFont(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.warning)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .padding(.vertical, 8)
                        .background(SpeedometerStyle.warning.opacity(0.14), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(SpeedometerStyle.warning.opacity(0.3), lineWidth: 1)
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(VeluraGlassPressButtonStyle())
                .accessibilityHint("Deletes the route only; drive statistics are kept")
            }
        }
        .padding(18)
        .veluraGlassCard(cornerRadius: 25, stroke: SpeedometerStyle.foreground.opacity(0.14))
    }

    private func elevationProfileCard(_ elevation: ElevationSummary) -> some View {
        let elevationUnit = usesMiles ? "ft" : "m"
        let factor = usesMiles ? 3.28084 : 1.0
        let gainValue = Int((elevation.gainMeters * factor).rounded())
        let lossValue = Int((elevation.lossMeters * factor).rounded())

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("ELEVATION", systemImage: "mountain.2.fill")
                    .modifier(AdaptiveFont(size: 10, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(SpeedometerStyle.secondary)
                Spacer()
                Text("+\(gainValue) \(elevationUnit) · -\(lossValue) \(elevationUnit)")
                    .modifier(AdaptiveFont(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(SpeedometerStyle.foreground)
            }

            Canvas { context, size in
                let samples = elevation.samples
                guard samples.count >= 2 else { return }
                let minAlt = elevation.minMeters
                let span = max(1, elevation.maxMeters - elevation.minMeters)

                var line = Path()
                var fill = Path()
                for (index, sample) in samples.enumerated() {
                    let x = CGFloat(index) / CGFloat(samples.count - 1) * size.width
                    let normalized = (sample.altitudeMeters - minAlt) / span
                    let y = size.height - CGFloat(normalized) * (size.height - 6) - 3
                    if index == 0 {
                        line.move(to: CGPoint(x: x, y: y))
                        fill.move(to: CGPoint(x: x, y: size.height))
                        fill.addLine(to: CGPoint(x: x, y: y))
                    } else {
                        line.addLine(to: CGPoint(x: x, y: y))
                        fill.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                fill.addLine(to: CGPoint(x: size.width, y: size.height))
                fill.closeSubpath()

                context.fill(
                    fill,
                    with: .linearGradient(
                        Gradient(colors: [SpeedometerStyle.accent.opacity(0.28), .clear]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
                context.stroke(
                    line,
                    with: .color(SpeedometerStyle.accent),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }
            .frame(height: 52)
        }
        .padding(12)
        .background(SpeedometerStyle.foreground.opacity(0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Elevation gain \(gainValue) \(elevationUnit), loss \(lossValue) \(elevationUnit)")
    }

    private var interruptionGapNotice: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(isOn: $showsRecordingGaps) {
                HStack(spacing: 8) {
                    Label("Recording gaps", systemImage: "location.slash")
                        .modifier(AdaptiveFont(size: 12, weight: .semibold, design: .rounded))
                    Text("\(drive.interruptionGaps.count)")
                        .modifier(AdaptiveFont(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                }
                .foregroundStyle(SpeedometerStyle.warning)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .tint(SpeedometerStyle.warning)
            .accessibilityHint("Shows or hides the gap details without changing saved route data")

            if showsRecordingGaps {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(drive.interruptionGaps) { gap in
                        Text("\(gap.startAt.formatted(date: .abbreviated, time: .shortened)) – \(gap.endAt.formatted(date: .abbreviated, time: .shortened))")
                            .modifier(AdaptiveFont(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(SpeedometerStyle.foreground)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("No speed, distance, or route points were estimated for these intervals.")
                        .modifier(AdaptiveFont(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(VeluraMotion.transition(.opacity.combined(with: .move(edge: .top)), reduceMotion: reduceMotion))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SpeedometerStyle.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion), value: showsRecordingGaps)
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .modifier(AdaptiveFont(size: 10, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(SpeedometerStyle.secondary)
            Text(value)
                .modifier(AdaptiveFont(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(SpeedometerStyle.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct RouteMapMarker: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 20, height: 20)
            .overlay {
                Circle()
                    .fill(AppAppearance.shared.theme.foreground(on: color))
                    .frame(width: 9, height: 9)
            }
            .shadow(color: color.opacity(0.55), radius: 8)
        .accessibilityHidden(true)
    }
}

private func routeDuration(_ duration: TimeInterval) -> String {
    let totalMinutes = max(0, Int(duration / 60))
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0 { return "\(hours)h \(minutes)m" }
    return "\(totalMinutes) min"
}

private struct RouteShareContent: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct RouteActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

private enum RouteShareError: Error {
    case snapshotUnavailable
}
