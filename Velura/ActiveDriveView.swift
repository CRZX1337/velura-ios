import MapKit
import SwiftUI

struct ActiveDriveView: View {
    @ObservedObject private var appearance = AppAppearance.shared
    @ObservedObject var model: SpeedometerModel
    @AppStorage("speedometer.usesMiles") private var usesMiles = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cameraPosition: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var showingEndConfirmation = false

    let onClose: () -> Void

    private var speedConversion: Double { usesMiles ? 0.621371 : 1 }
    private var distanceUnit: String { usesMiles ? "mi" : "km" }
    private var speedUnit: String { usesMiles ? "mph" : "km/h" }

    private var routeSegments: [[CLLocationCoordinate2D]] {
        var segments: [[CLLocationCoordinate2D]] = []
        var currentSegmentIndex: Int?
        for point in model.routeCoordinates {
            if currentSegmentIndex != point.segmentIndex {
                segments.append([])
                currentSegmentIndex = point.segmentIndex
            }
            segments[segments.count - 1].append(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
        }
        return segments
    }

    private var routeRegion: MKCoordinateRegion {
        let points = model.routeCoordinates
        guard !points.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )
        }

        let minimumLatitude = points.map(\.latitude).min() ?? 0
        let maximumLatitude = points.map(\.latitude).max() ?? 0
        let minimumLongitude = points.map(\.longitude).min() ?? 0
        let maximumLongitude = points.map(\.longitude).max() ?? 0
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minimumLatitude + maximumLatitude) / 2,
                longitude: (minimumLongitude + maximumLongitude) / 2
            ),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.008, (maximumLatitude - minimumLatitude) * 1.45),
                longitudeDelta: max(0.008, (maximumLongitude - minimumLongitude) * 1.45)
            )
        )
    }

    var body: some View {
        ZStack {
            routeMap

            VStack(spacing: 0) {
                header
                Spacer(minLength: 16)
                summaryCard
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(appearance.background)
        .preferredColorScheme(appearance.preferredColorScheme)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear(perform: fitRoute)
        .confirmationDialog("End this drive?", isPresented: $showingEndConfirmation, titleVisibility: .visible) {
            Button("End drive and save", role: .destructive) {
                model.finishSession()
                onClose()
            }
            Button("Keep driving", role: .cancel) { }
        } message: {
            Text("The recorded drive summary will be saved to your history.")
        }
    }

    private var routeMap: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
            UserAnnotation()

            ForEach(routeSegments.indices, id: \.self) { index in
                let segment = routeSegments[index]
                if segment.count > 1 {
                    MapPolyline(coordinates: segment)
                        .stroke(SpeedometerStyle.accent, lineWidth: 5)
                }
            }

            if let start = model.routeCoordinates.first {
                Annotation("Start", coordinate: CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude), anchor: .center) {
                    routeMarker(color: SpeedometerStyle.mint, symbol: "play.fill")
                }
            }

            if let latest = model.routeCoordinates.last {
                Annotation("Current location", coordinate: CLLocationCoordinate2D(latitude: latest.latitude, longitude: latest.longitude), anchor: .center) {
                    routeMarker(color: SpeedometerStyle.warning, symbol: "location.fill")
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .ignoresSafeArea()
        .accessibilityLabel("Live drive route map")
    }

    private func fitRoute() {
        guard !model.routeCoordinates.isEmpty else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) {
            cameraPosition = .region(routeRegion)
        }
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(SpeedometerStyle.foreground)
                    .frame(width: 54, height: 54)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(SpeedometerStyle.foreground.opacity(0.18), lineWidth: 1))
            }
            .accessibilityLabel("Close active drive")

            Spacer(minLength: 8)
            Text("Drive")
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(SpeedometerStyle.foreground)
            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button(action: fitRoute) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SpeedometerStyle.foreground)
                        .frame(width: 48, height: 48)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(SpeedometerStyle.foreground.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(model.routeCoordinates.isEmpty)
                .accessibilityLabel("Fit recorded route")
                .accessibilityHint("Fits the map to the latest recorded route")

                Menu {
                    Button("End drive", systemImage: "stop.fill", role: .destructive) {
                        showingEndConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(SpeedometerStyle.foreground)
                        .frame(width: 54, height: 54)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(SpeedometerStyle.foreground.opacity(0.18), lineWidth: 1))
                }
                .accessibilityLabel("More drive options")
            }
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 13) {
            Capsule()
                .fill(SpeedometerStyle.secondary.opacity(0.52))
                .frame(width: 48, height: 5)
                .padding(.bottom, 1)

            HStack(spacing: 8) {
                Text(model.isSessionActive ? "DRIVE ACTIVE" : "DRIVE PAUSED")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(SpeedometerStyle.secondary)
                Circle()
                    .fill(model.isSessionActive ? SpeedometerStyle.mint : SpeedometerStyle.warning)
                    .frame(width: 9, height: 9)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int((model.speedKmh * speedConversion).rounded()))")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(SpeedometerStyle.foreground)
                Text(speedUnit)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Current speed, \(Int((model.speedKmh * speedConversion).rounded())) \(speedUnit)")

            Rectangle()
                .fill(SpeedometerStyle.secondary.opacity(0.25))
                .frame(height: 1)

            HStack(spacing: 0) {
                summaryMetric(title: "DISTANCE", value: String(format: "%.1f %@", model.distanceKm * (usesMiles ? 0.621371 : 1), distanceUnit))
                metricDivider
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    summaryMetric(title: "TIME", value: formattedDuration(model.elapsedTime(at: context.date)))
                }
                metricDivider
                summaryMetric(title: "TOP SPEED", value: "\(Int((model.topSpeedKmh * speedConversion).rounded())) \(speedUnit)")
            }

            Button {
                showingEndConfirmation = true
            } label: {
                Label("End drive", systemImage: "stop.fill")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.warning)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 58)
                    .background(SpeedometerStyle.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(SpeedometerStyle.accent.opacity(0.18), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ends location tracking and saves the recorded drive summary")
        }
        .padding(.horizontal, 17)
        .padding(.top, 11)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(SpeedometerStyle.background.opacity(0.82), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(SpeedometerStyle.foreground.opacity(0.17), lineWidth: 1)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(SpeedometerStyle.secondary.opacity(0.24))
            .frame(width: 1, height: 48)
            .padding(.horizontal, 10)
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(SpeedometerStyle.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .tracking(0.65)
                .foregroundStyle(SpeedometerStyle.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private func routeMarker(color: Color, symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(color, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
    }
}

private func formattedDuration(_ interval: TimeInterval) -> String {
    let totalSeconds = max(0, Int(interval))
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
        : String(format: "%d:%02d", minutes, seconds)
}
