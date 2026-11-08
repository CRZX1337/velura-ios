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
    @ObservedObject private var appearance = AppAppearance.shared
    @AppStorage("speedometer.usesMiles") private var usesMiles = false
    @State private var routeCoordinates: [DriveRoutePoint]
    @State private var showsRecordingGaps = true
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
                        Text(dateChipText)
                            .modifier(AdaptiveFont(size: 12, weight: .semibold, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(SpeedometerStyle.foreground.opacity(0.88))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .glassEffect(.regular, in: .capsule)
                            .padding(.top, 8)
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
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The route will be removed from this device. Drive statistics will be kept.")
        }
        .sheet(item: $shareContent) { content in
            RouteActivityView(activityItems: [content.message, content.mapImage])
        }
        .alert("Unable to share route", isPresented: $showingShareError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(shareErrorMessage)
        }
    }

    private var routeMap: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
            ForEach(routeSegments.indices, id: \.self) { index in
                let segment = routeSegments[index]
                if segment.count > 1 {
                    MapPolyline(coordinates: segment)
                        .stroke(SpeedometerStyle.accent, lineWidth: 5)
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

    private var emptyMapState: some View {
        ZStack {
            SpeedometerStyle.background
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
            .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var header: some View {
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
                    .modifier(AdaptiveFont(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.foreground)
                    .lineLimit(1)
                Spacer()
                headerShareButton
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
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to drive details")
    }

    @ViewBuilder
    private var headerShareButton: some View {
        if routeCoordinates.count >= 2 {
            Button {
                Task { await prepareShare() }
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
                .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(isPreparingShare)
            .accessibilityLabel("Share drive route")
            .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: isPreparingShare)
        } else {
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
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
            shareContent = RouteShareContent(message: messageLines.joined(separator: "\n"), mapImage: mapImage)
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
                        .glassEffect(.regular.tint(SpeedometerStyle.warning.opacity(0.12)), in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Deletes the route only; drive statistics are kept")
            }
        }
        .padding(18)
        .background(SpeedometerStyle.foreground.opacity(0.025), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 25))
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
    let message: String
    let mapImage: UIImage
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
