import MapKit
import SwiftUI

enum ActiveMapCameraMode: Equatable {
    case followUser
    case followHeading
    case overview
    case manual
}

struct ActiveDriveView: View {
    @ObservedObject private var appearance = AppAppearance.shared
    @ObservedObject var model: SpeedometerModel
    @AppStorage("speedometer.usesMiles") private var usesMiles = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var mapHeaderGlassNamespace
    @Namespace private var mapControlsGlassNamespace
    @State private var cameraPosition: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var cameraMode: ActiveMapCameraMode = .followHeading
    @State private var isProgrammaticCameraUpdate = false
    @State private var showingEndConfirmation = false

    let onClose: () -> Void

    private var speedConversion: Double { usesMiles ? 0.621371 : 1 }
    private var distanceUnit: String { usesMiles ? "mi" : "km" }
    private var speedUnit: String { usesMiles ? "mph" : "km/h" }
    private var displayedSpeed: Int { Int((model.displaySpeedKmh * speedConversion).rounded()) }

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

            VStack(spacing: 12) {
                header

                HStack {
                    Spacer()
                    mapCameraControls
                }

                Spacer(minLength: 10)
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
        .sensoryFeedback(.selection, trigger: cameraMode)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.isSessionActive)
        .onAppear {
            if model.isSessionActive {
                applyCameraMode(.followHeading)
            } else if !model.routeCoordinates.isEmpty {
                applyCameraMode(.overview)
            }
        }
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
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom, .rotate]) {
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
        .onMapCameraChange(frequency: .onEnd) { _ in
            if isProgrammaticCameraUpdate {
                isProgrammaticCameraUpdate = false
            } else {
                cameraMode = .manual
            }
        }
        .ignoresSafeArea()
        .accessibilityLabel("Live drive route map")
    }

    private func applyCameraMode(_ mode: ActiveMapCameraMode) {
        cameraMode = mode
        isProgrammaticCameraUpdate = true
        withAnimation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion)) {
            switch mode {
            case .followUser:
                cameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
            case .followHeading:
                cameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
            case .overview:
                if !model.routeCoordinates.isEmpty {
                    cameraPosition = .region(routeRegion)
                } else {
                    cameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
                }
            case .manual:
                break
            }
        }
    }

    private func fitRoute() {
        guard !model.routeCoordinates.isEmpty else { return }
        applyCameraMode(.overview)
    }

    private var mapCameraControls: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                cameraControlButton(
                    symbol: "location.fill",
                    isActive: cameraMode == .followUser,
                    id: "active-map-follow",
                    label: "Auto-follow location"
                ) {
                    applyCameraMode(.followUser)
                }

                cameraControlButton(
                    symbol: "location.north.line.fill",
                    isActive: cameraMode == .followHeading,
                    id: "active-map-heading",
                    label: "Follow heading"
                ) {
                    applyCameraMode(.followHeading)
                }

                cameraControlButton(
                    symbol: "map",
                    isActive: cameraMode == .overview,
                    id: "active-map-overview",
                    label: "Show full route"
                ) {
                    fitRoute()
                }
                .disabled(model.routeCoordinates.isEmpty)
                .opacity(model.routeCoordinates.isEmpty ? 0.45 : 1)
            }
        }
    }

    private func cameraControlButton(
        symbol: String,
        isActive: Bool,
        id: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .modifier(AdaptiveFont(size: 16, weight: .semibold))
                .foregroundStyle(isActive ? SpeedometerStyle.accentForeground : SpeedometerStyle.foreground)
                .frame(width: 46, height: 46)
                .background {
                    if isActive {
                        Circle().fill(SpeedometerStyle.accent)
                    }
                }
                .contentShape(Circle())
                .veluraGlassCircle(tint: isActive ? nil : .clear, interactive: true)
                .glassEffectID(id, in: mapControlsGlassNamespace)
        }
        .buttonStyle(VeluraGlassPressButtonStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var header: some View {
        GlassEffectContainer(spacing: 10) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .modifier(AdaptiveFont(size: 17, weight: .semibold))
                        .foregroundStyle(SpeedometerStyle.foreground)
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                        .veluraGlassCircle(interactive: true)
                        .glassEffectID("active-drive-back", in: mapHeaderGlassNamespace)
                }
                .buttonStyle(VeluraGlassPressButtonStyle())
                .accessibilityLabel("Close active drive")

                Spacer(minLength: 8)
                Text("Drive")
                    .modifier(AdaptiveFont(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.foreground)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .veluraGlassCapsule()
                    .glassEffectID("active-drive-title", in: mapHeaderGlassNamespace)
                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    Button(action: fitRoute) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .modifier(AdaptiveFont(size: 15, weight: .semibold))
                            .foregroundStyle(SpeedometerStyle.foreground)
                            .frame(width: 48, height: 48)
                            .contentShape(Circle())
                            .veluraGlassCircle(interactive: true)
                            .glassEffectID("active-drive-fit", in: mapHeaderGlassNamespace)
                    }
                    .buttonStyle(VeluraGlassPressButtonStyle())
                    .disabled(model.routeCoordinates.isEmpty)
                    .opacity(model.routeCoordinates.isEmpty ? 0.5 : 1)
                    .accessibilityLabel("Fit recorded route")
                    .accessibilityHint("Fits the map to the latest recorded route")

                    Menu {
                        Button("End drive", systemImage: "stop.fill", role: .destructive) {
                            showingEndConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .modifier(AdaptiveFont(size: 17, weight: .semibold))
                            .foregroundStyle(SpeedometerStyle.foreground)
                            .frame(width: 48, height: 48)
                            .contentShape(Circle())
                            .veluraGlassCircle(interactive: true)
                            .glassEffectID("active-drive-menu", in: mapHeaderGlassNamespace)
                    }
                    .accessibilityLabel("More drive options")
                }
            }
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 13) {
            Capsule()
                .fill(SpeedometerStyle.secondary.opacity(0.45))
                .frame(width: 44, height: 4.5)
                .padding(.bottom, 1)

            HStack(spacing: 8) {
                Text(model.isSessionActive ? "DRIVE ACTIVE" : "DRIVE PAUSED")
                    .modifier(AdaptiveFont(size: 11, weight: .semibold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(SpeedometerStyle.secondary)
                Circle()
                    .fill(model.isSessionActive ? SpeedometerStyle.mint : SpeedometerStyle.warning)
                    .frame(width: 8, height: 8)
                    .shadow(color: (model.isSessionActive ? SpeedometerStyle.mint : SpeedometerStyle.warning).opacity(0.5), radius: 4)
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(displayedSpeed)")
                    .modifier(AdaptiveFont(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                    .foregroundStyle(SpeedometerStyle.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(speedUnit)
                    .modifier(AdaptiveFont(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Current speed, \(displayedSpeed) \(speedUnit)")
            .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: displayedSpeed)

            Rectangle()
                .fill(SpeedometerStyle.foreground.opacity(0.14))
                .frame(height: 1)

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 10) {
                        summaryMetric(title: "DISTANCE", value: String(format: "%.1f %@", model.distanceKm * speedConversion, distanceUnit))
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            summaryMetric(title: "TIME", value: formattedDuration(model.elapsedTime(at: context.date)))
                        }
                        summaryMetric(title: "TOP SPEED", value: "\(Int((model.topSpeedKmh * speedConversion).rounded())) \(speedUnit)")
                    }
                } else {
                    HStack(spacing: 0) {
                        summaryMetric(title: "DISTANCE", value: String(format: "%.1f %@", model.distanceKm * speedConversion, distanceUnit))
                        metricDivider
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            summaryMetric(title: "TIME", value: formattedDuration(model.elapsedTime(at: context.date)))
                        }
                        metricDivider
                        summaryMetric(title: "TOP SPEED", value: "\(Int((model.topSpeedKmh * speedConversion).rounded())) \(speedUnit)")
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation(VeluraMotion.animation(VeluraMotion.morph, reduceMotion: reduceMotion)) {
                        if model.isSessionActive {
                            model.pauseSession()
                        } else {
                            model.startSession()
                        }
                    }
                } label: {
                    Label(
                        model.isSessionActive ? "Pause" : "Resume",
                        systemImage: model.isSessionActive ? "pause.fill" : "play.fill"
                    )
                    .modifier(AdaptiveFont(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.accentForeground)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(SpeedometerStyle.accent, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(VeluraGlassPressButtonStyle())
                .disabled(model.isDriveStorageLoading || model.isFinishingSession)
                .accessibilityHint(model.isSessionActive ? "Pauses GPS recording without ending the drive" : "Resumes recording into a new route segment")

                Button {
                    showingEndConfirmation = true
                } label: {
                    Label("End", systemImage: "stop.fill")
                        .modifier(AdaptiveFont(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.warning)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(SpeedometerStyle.warning.opacity(0.14), in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(SpeedometerStyle.warning.opacity(0.32), lineWidth: 1)
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(VeluraGlassPressButtonStyle())
                .disabled(model.isFinishingSession)
                .accessibilityHint("Ends location tracking and saves the recorded drive summary")
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, 11)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .veluraGlassCard(cornerRadius: 28, stroke: SpeedometerStyle.foreground.opacity(0.16))
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.isSessionActive)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(SpeedometerStyle.foreground.opacity(0.14))
            .frame(width: 1, height: 44)
            .padding(.horizontal, 10)
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .modifier(AdaptiveFont(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(SpeedometerStyle.foreground)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .modifier(AdaptiveFont(size: 10, weight: .medium, design: .rounded))
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
