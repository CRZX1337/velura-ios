import MapKit
import SwiftUI
import UIKit

enum DriveModeLayout: String, CaseIterable, Identifiable {
    case classic
    case modern
    case navigation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .modern: "Modern"
        case .navigation: "Map"
        }
    }

    var fullTitle: String {
        switch self {
        case .classic: "Classic Cockpit"
        case .modern: "Modern Dashboard"
        case .navigation: "Navigation Cockpit"
        }
    }

    var symbol: String {
        switch self {
        case .classic: "gauge.with.dots.needle.67percent"
        case .modern: "square.grid.2x2"
        case .navigation: "map"
        }
    }
}

enum DriveModeMapCameraMode: Equatable {
    case followUser
    case followHeading
    case overview
    case manual
}

struct DriveModeView: View {
    @ObservedObject var model: SpeedometerModel
    @ObservedObject private var appearance = AppAppearance.shared
    @StateObject private var media = DriveMediaController()

    @AppStorage("speedometer.usesMiles") private var usesMiles = false
    @AppStorage("speedometer.selectedRange") private var selectedRange = 50
    @AppStorage("speedometer.customRange") private var customRange = 160
    @AppStorage("speedometer.driveMode.layout") private var layoutRawValue = DriveModeLayout.modern.rawValue
    @AppStorage("speedometer.driveMode.showsMediaWidget") private var showsMediaWidget = false
    @AppStorage("speedometer.driveMode.destination") private var savedDestination = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.openURL) private var openURL

    @Namespace private var layoutSelectionNamespace
    @Namespace private var cockpitHeaderNamespace
    @Namespace private var cockpitActionsNamespace

    @State private var cameraPosition: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var cameraMode: DriveModeMapCameraMode = .followHeading
    @State private var isProgrammaticCameraUpdate = false
    @State private var showingEndConfirmation = false
    @State private var showingDestinationSheet = false
    @State private var destinationDraft = ""

    let onClose: () -> Void

    private var selectedLayout: DriveModeLayout {
        DriveModeLayout(rawValue: layoutRawValue) ?? .modern
    }

    private var conversion: Double { usesMiles ? 0.621371 : 1 }
    private var speedUnit: String { usesMiles ? "mph" : "km/h" }
    private var distanceUnit: String { usesMiles ? "mi" : "km" }
    private var rangeMaximum: Double { Double(selectedRange == -1 ? customRange : selectedRange) }
    private var displayedSpeed: Double { model.displaySpeedKmh * conversion }
    private var displayedTopSpeed: Double { model.topSpeedKmh * conversion }
    private var displayedDistance: Double { model.distanceKm * conversion }

    private var speedIntensity: Double {
        guard rangeMaximum > 0 else { return 0 }
        return min(max(displayedSpeed / rangeMaximum, 0), 1)
    }

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
                center: model.currentCoordinate() ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
            )
        }
        let minLat = points.map(\.latitude).min() ?? 0
        let maxLat = points.map(\.latitude).max() ?? 0
        let minLon = points.map(\.longitude).min() ?? 0
        let maxLon = points.map(\.longitude).max() ?? 0
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.008, (maxLat - minLat) * 1.45),
                longitudeDelta: max(0.008, (maxLon - minLon) * 1.45)
            )
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let horizontalInset: CGFloat = geometry.size.width < 380 ? 14 : (isLandscape ? 22 : 18)

            ZStack {
                if selectedLayout == .navigation {
                    cockpitMap
                } else {
                    VeluraAmbientBackdrop(
                        intensity: speedIntensity,
                        isWarning: model.isOverspeedWarningActive,
                        isActive: model.isSessionActive
                    )
                }

                VStack(spacing: isLandscape ? 10 : 14) {
                    topBar(isLandscape: isLandscape)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        switch selectedLayout {
                        case .classic:
                            classicCockpit(size: geometry.size, isLandscape: isLandscape, now: context.date)
                                .transition(VeluraMotion.transition(.opacity.combined(with: .scale(scale: 0.98)), reduceMotion: reduceMotion))
                        case .modern:
                            modernDashboard(size: geometry.size, isLandscape: isLandscape, now: context.date)
                                .transition(VeluraMotion.transition(.opacity.combined(with: .scale(scale: 0.98)), reduceMotion: reduceMotion))
                        case .navigation:
                            navigationCockpitOverlay(isLandscape: isLandscape, now: context.date)
                                .transition(VeluraMotion.transition(.opacity, reduceMotion: reduceMotion))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showsMediaWidget {
                        mediaWidgetBar
                            .transition(VeluraMotion.transition(.move(edge: .bottom).combined(with: .opacity), reduceMotion: reduceMotion))
                    }

                    bottomControlBar(isLandscape: isLandscape)
                }
                .padding(.horizontal, horizontalInset)
                .padding(.top, isLandscape ? 8 : 10)
                .padding(.bottom, isLandscape ? 8 : 12)
                .frame(maxWidth: isLandscape ? 920 : 560)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(appearance.preferredColorScheme)
        .sensoryFeedback(.selection, trigger: layoutRawValue)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.isSessionActive)
        .animation(VeluraMotion.animation(VeluraMotion.morph, reduceMotion: reduceMotion), value: layoutRawValue)
        .animation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion), value: showsMediaWidget)
        .onAppear {
            if showsMediaWidget {
                media.startMonitoring()
            }
        }
        .onChange(of: showsMediaWidget) { _, visible in
            if visible {
                media.startMonitoring()
            } else {
                media.stopMonitoring()
            }
        }
        .onDisappear {
            media.stopMonitoring()
        }
        .confirmationDialog("Finish this drive?", isPresented: $showingEndConfirmation, titleVisibility: .visible) {
            Button("Finish & save drive", role: .destructive) {
                model.finishSession()
            }
            Button("Keep driving", role: .cancel) { }
        } message: {
            Text("The recorded drive summary and route will be saved to your history.")
        }
        .sheet(isPresented: $showingDestinationSheet) {
            externalNavigationSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Top Bar

    private func topBar(isLandscape: Bool) -> some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .modifier(AdaptiveFont(size: 16, weight: .semibold))
                        .foregroundStyle(SpeedometerStyle.foreground)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .veluraGlassCircle(interactive: true)
                        .glassEffectID("drive-mode-close", in: cockpitHeaderNamespace)
                }
                .buttonStyle(VeluraGlassPressButtonStyle())
                .accessibilityLabel("Exit Drive Mode")

                layoutSwitcher

                Spacer(minLength: 4)

                if !isLandscape {
                    gpsBadgeCompact
                } else {
                    driveStatePill
                    gpsBadgeCompact
                }

                Menu {
                    Toggle(isOn: $showsMediaWidget) {
                        Label("Music widget", systemImage: "music.note")
                    }
                    Button {
                        destinationDraft = savedDestination
                        showingDestinationSheet = true
                    } label: {
                        Label("Navigate in Apple Maps", systemImage: "map.fill")
                    }
                    if !savedDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            openAppleMaps(destination: savedDestination)
                        } label: {
                            Label("Open \"\(savedDestination)\"", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .modifier(AdaptiveFont(size: 16, weight: .semibold))
                        .foregroundStyle(SpeedometerStyle.foreground)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .veluraGlassCircle(interactive: true)
                        .glassEffectID("drive-mode-more", in: cockpitHeaderNamespace)
                }
                .accessibilityLabel("Drive Mode options")
            }
        }
    }

    private var layoutSwitcher: some View {
        HStack(spacing: 3) {
            ForEach(DriveModeLayout.allCases) { layout in
                let isSelected = selectedLayout == layout
                Button {
                    withAnimation(VeluraMotion.animation(VeluraMotion.selection, reduceMotion: reduceMotion)) {
                        layoutRawValue = layout.rawValue
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: layout.symbol)
                            .modifier(AdaptiveFont(size: 12, weight: .semibold))
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text(layout.title)
                                .modifier(AdaptiveFont(size: 12, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(isSelected ? SpeedometerStyle.accentForeground : SpeedometerStyle.secondary)
                    .padding(.horizontal, 11)
                    .frame(minHeight: 38)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(SpeedometerStyle.accent)
                                .matchedGeometryEffect(id: "driveModeLayoutSelection", in: layoutSelectionNamespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(VeluraGlassPressButtonStyle())
                .accessibilityLabel(layout.fullTitle)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .veluraGlassCapsule(stroke: SpeedometerStyle.foreground.opacity(0.11))
        .glassEffectID("drive-mode-layout", in: cockpitHeaderNamespace)
    }

    private var driveStatePill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(driveStateColor)
                .frame(width: 8, height: 8)
                .shadow(color: driveStateColor.opacity(0.55), radius: 4)
            Text(model.driveState.badgeTitle)
                .modifier(AdaptiveFont(size: 11, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(SpeedometerStyle.foreground)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .veluraGlassCapsule()
        .glassEffectID("drive-mode-state", in: cockpitHeaderNamespace)
    }

    private var driveStateColor: Color {
        switch model.driveState {
        case .active: SpeedometerStyle.mint
        case .paused: Color.orange
        case .finishing: SpeedometerStyle.accent
        case .idle: SpeedometerStyle.secondary
        }
    }

    private var gpsBadgeCompact: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.isGPSReadingReliable ? SpeedometerStyle.mint : Color.orange)
                .frame(width: 8, height: 8)
            Text(gpsShortLabel)
                .modifier(AdaptiveFont(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(SpeedometerStyle.foreground)
                .lineLimit(1)
        }
        .padding(.horizontal, 11)
        .frame(minHeight: 40)
        .veluraGlassCapsule()
        .glassEffectID("drive-mode-gps", in: cockpitHeaderNamespace)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.gpsStatusTitle), \(model.gpsStatusDetail)")
    }

    private var gpsShortLabel: String {
        if model.isGPSReadingReliable {
            return "±\(Int(model.horizontalAccuracy.rounded()))m"
        }
        return model.isSessionActive ? "GPS…" : "GPS"
    }

    // MARK: - 1. Classic Cockpit

    @ViewBuilder
    private func classicCockpit(size: CGSize, isLandscape: Bool, now: Date) -> some View {
        let avgSpeed = model.averageSpeedKmh(at: now) * conversion
        let duration = model.elapsedTime(at: now)
        let moving = model.movingTime(at: now)

        if isLandscape {
            HStack(spacing: 18) {
                SpeedometerGauge(
                    speed: displayedSpeed,
                    maximum: rangeMaximum,
                    dialStyle: appearance.dialStyle == .digitalHUD || appearance.dialStyle == .verticalBar
                        ? .classic
                        : appearance.dialStyle,
                    displayScale: .prominent,
                    unit: speedUnit,
                    isOverspeed: model.isOverspeedWarningActive
                )
                .frame(maxWidth: size.width * 0.48, maxHeight: .infinity)

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        cockpitMetricTile(title: "AVG SPEED", value: "\(Int(avgSpeed.rounded())) \(speedUnit)", accent: SpeedometerStyle.accent)
                        cockpitMetricTile(title: "MAX SPEED", value: "\(Int(displayedTopSpeed.rounded())) \(speedUnit)", accent: SpeedometerStyle.mint)
                    }
                    HStack(spacing: 10) {
                        cockpitMetricTile(title: "DISTANCE", value: String(format: "%.1f %@", displayedDistance, distanceUnit))
                        cockpitMetricTile(title: "DURATION", value: cockpitDuration(duration))
                    }
                    HStack(spacing: 10) {
                        cockpitMetricTile(title: "MOVING", value: cockpitDuration(moving))
                        cockpitMetricTile(title: "GPS", value: model.isGPSReadingReliable ? "±\(Int(model.horizontalAccuracy.rounded())) m" : model.gpsStatusTitle)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    driveStateBanner

                    SpeedometerGauge(
                        speed: displayedSpeed,
                        maximum: rangeMaximum,
                        dialStyle: appearance.dialStyle == .digitalHUD || appearance.dialStyle == .verticalBar
                            ? .classic
                            : appearance.dialStyle,
                        displayScale: .prominent,
                        unit: speedUnit,
                        isOverspeed: model.isOverspeedWarningActive
                    )
                    .frame(height: min(max(size.height * 0.37, 230), 330))

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                        spacing: 10
                    ) {
                        cockpitMetricTile(title: "AVG SPEED", value: "\(Int(avgSpeed.rounded())) \(speedUnit)", accent: SpeedometerStyle.accent)
                        cockpitMetricTile(title: "MAX SPEED", value: "\(Int(displayedTopSpeed.rounded())) \(speedUnit)", accent: SpeedometerStyle.mint)
                        cockpitMetricTile(title: "DISTANCE", value: String(format: "%.1f %@", displayedDistance, distanceUnit))
                        cockpitMetricTile(title: "DURATION", value: cockpitDuration(duration))
                        cockpitMetricTile(title: "MOVING", value: cockpitDuration(moving))
                        cockpitMetricTile(title: "GPS SIGNAL", value: model.isGPSReadingReliable ? "Locked · ±\(Int(model.horizontalAccuracy.rounded()))m" : model.gpsStatusTitle)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - 2. Modern Dashboard (Default)

    @ViewBuilder
    private func modernDashboard(size: CGSize, isLandscape: Bool, now: Date) -> some View {
        let avgSpeed = model.averageSpeedKmh(at: now) * conversion
        let duration = model.elapsedTime(at: now)
        let moving = model.movingTime(at: now)

        if isLandscape {
            HStack(spacing: 16) {
                modernSpeedHeroCard(isLandscape: true)
                    .frame(maxWidth: size.width * 0.46, maxHeight: .infinity)

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        cockpitMetricTile(title: "AVG SPEED", value: "\(Int(avgSpeed.rounded())) \(speedUnit)", accent: SpeedometerStyle.accent)
                        cockpitMetricTile(title: "MAX SPEED", value: "\(Int(displayedTopSpeed.rounded())) \(speedUnit)", accent: SpeedometerStyle.mint)
                    }
                    HStack(spacing: 10) {
                        cockpitMetricTile(title: "DISTANCE", value: String(format: "%.1f %@", displayedDistance, distanceUnit))
                        cockpitMetricTile(title: "DRIVE TIME", value: cockpitDuration(duration))
                    }
                    HStack(spacing: 10) {
                        cockpitMetricTile(title: "MOVING TIME", value: cockpitDuration(moving))
                        cockpitMetricTile(
                            title: "GPS STATUS",
                            value: model.isGPSReadingReliable ? "Locked · ±\(Int(model.horizontalAccuracy.rounded()))m" : model.gpsStatusTitle
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    modernSpeedHeroCard(isLandscape: false)

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                        spacing: 10
                    ) {
                        cockpitMetricTile(title: "AVG SPEED", value: "\(Int(avgSpeed.rounded())) \(speedUnit)", accent: SpeedometerStyle.accent)
                        cockpitMetricTile(title: "MAX SPEED", value: "\(Int(displayedTopSpeed.rounded())) \(speedUnit)", accent: SpeedometerStyle.mint)
                        cockpitMetricTile(title: "DISTANCE", value: String(format: "%.1f %@", displayedDistance, distanceUnit))
                        cockpitMetricTile(title: "DRIVE TIME", value: cockpitDuration(duration))
                        cockpitMetricTile(title: "MOVING TIME", value: cockpitDuration(moving))
                        cockpitMetricTile(
                            title: "GPS ACCURACY",
                            value: model.isGPSReadingReliable ? "±\(Int(model.horizontalAccuracy.rounded())) m" : model.gpsStatusTitle
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func modernSpeedHeroCard(isLandscape: Bool) -> some View {
        let gaugeColor = model.isOverspeedWarningActive ? SpeedometerStyle.warning : SpeedometerStyle.accent
        return VStack(alignment: .leading, spacing: isLandscape ? 10 : 14) {
            HStack {
                HStack(spacing: 7) {
                    Circle()
                        .fill(driveStateColor)
                        .frame(width: 9, height: 9)
                        .shadow(color: driveStateColor.opacity(0.6), radius: 5)
                    Text(model.driveState.badgeTitle)
                        .modifier(AdaptiveFont(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(SpeedometerStyle.secondary)
                }
                Spacer()
                Text(model.gpsStatusTitle)
                    .modifier(AdaptiveFont(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(model.isGPSReadingReliable ? SpeedometerStyle.mint : SpeedometerStyle.secondary)
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(Int(displayedSpeed.rounded()))")
                    .font(.system(size: isLandscape ? 88 : 96, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(model.isOverspeedWarningActive ? SpeedometerStyle.warning : SpeedometerStyle.foreground)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                Text(speedUnit)
                    .modifier(AdaptiveFont(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Current speed \(Int(displayedSpeed.rounded())) \(speedUnit)")

            GeometryReader { barProxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(SpeedometerStyle.foreground.opacity(0.14))
                    Capsule()
                        .fill(LinearGradient(colors: [gaugeColor, SpeedometerStyle.mint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, barProxy.size.width * CGFloat(speedIntensity)))
                        .shadow(color: gaugeColor.opacity(0.45), radius: 8)
                }
            }
            .frame(height: 9)
            .animation(VeluraMotion.animation(VeluraMotion.gauge, reduceMotion: reduceMotion), value: speedIntensity)

            HStack {
                Text("0")
                Spacer()
                Text("Range \(Int(rangeMaximum)) \(speedUnit)")
            }
            .modifier(AdaptiveFont(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(SpeedometerStyle.secondary)
        }
        .padding(isLandscape ? 18 : 22)
        .frame(maxWidth: .infinity, minHeight: isLandscape ? 170 : 210)
        .veluraGlassCard(
            cornerRadius: 28,
            tint: model.isOverspeedWarningActive ? SpeedometerStyle.warning.opacity(0.16) : nil,
            stroke: gaugeColor.opacity(0.28)
        )
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: displayedSpeed)
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.isOverspeedWarningActive)
    }

    // MARK: - 3. Navigation Cockpit

    private var cockpitMap: some View {
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
                    Circle()
                        .fill(SpeedometerStyle.mint)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: 2.5))
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
        .accessibilityLabel("Navigation Cockpit live map")
    }

    private func navigationCockpitOverlay(isLandscape: Bool, now: Date) -> some View {
        let avgSpeed = model.averageSpeedKmh(at: now) * conversion
        let duration = model.elapsedTime(at: now)

        return VStack(spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(Int(displayedSpeed.rounded()))")
                            .font(.system(size: isLandscape ? 54 : 60, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(model.isOverspeedWarningActive ? SpeedometerStyle.warning : SpeedometerStyle.foreground)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(speedUnit)
                            .modifier(AdaptiveFont(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(SpeedometerStyle.secondary)
                    }
                    Text("AVG \(Int(avgSpeed.rounded())) · MAX \(Int(displayedTopSpeed.rounded()))")
                        .modifier(AdaptiveFont(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(SpeedometerStyle.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .veluraGlassCard(
                    cornerRadius: 22,
                    tint: model.isOverspeedWarningActive ? SpeedometerStyle.warning.opacity(0.18) : nil,
                    stroke: SpeedometerStyle.foreground.opacity(0.16)
                )

                Spacer(minLength: 8)

                VStack(spacing: 8) {
                    mapCameraButton(
                        symbol: cameraMode == .followHeading ? "location.north.line.fill" : "location.fill",
                        isActive: cameraMode == .followHeading || cameraMode == .followUser,
                        label: cameraMode == .followHeading ? "Heading follow active" : "Follow location"
                    ) {
                        if cameraMode == .followHeading {
                            setMapCamera(.followUser)
                        } else {
                            setMapCamera(.followHeading)
                        }
                    }

                    mapCameraButton(
                        symbol: "map",
                        isActive: cameraMode == .overview,
                        label: "Route overview"
                    ) {
                        setMapCamera(.overview)
                    }
                    .disabled(model.routeCoordinates.isEmpty)
                    .opacity(model.routeCoordinates.isEmpty ? 0.45 : 1)

                    mapCameraButton(
                        symbol: "arrow.triangle.turn.up.right.diamond.fill",
                        isActive: false,
                        label: "Open in Apple Maps"
                    ) {
                        destinationDraft = savedDestination
                        showingDestinationSheet = true
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                compactStripMetric(title: "DIST", value: String(format: "%.1f %@", displayedDistance, distanceUnit))
                Rectangle().fill(SpeedometerStyle.foreground.opacity(0.14)).frame(width: 1, height: 28)
                compactStripMetric(title: "TIME", value: cockpitDuration(duration))
                Rectangle().fill(SpeedometerStyle.foreground.opacity(0.14)).frame(width: 1, height: 28)
                compactStripMetric(title: "MOVING", value: cockpitDuration(model.movingTime(at: now)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .veluraGlassCard(cornerRadius: 20, stroke: SpeedometerStyle.foreground.opacity(0.14))
        }
    }

    private func mapCameraButton(
        symbol: String,
        isActive: Bool,
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
        }
        .buttonStyle(VeluraGlassPressButtonStyle())
        .accessibilityLabel(label)
    }

    private func setMapCamera(_ mode: DriveModeMapCameraMode) {
        cameraMode = mode
        isProgrammaticCameraUpdate = true
        withAnimation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion)) {
            switch mode {
            case .followUser:
                cameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
            case .followHeading:
                cameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
            case .overview:
                cameraPosition = .region(routeRegion)
            case .manual:
                break
            }
        }
    }

    // MARK: - Media Widget (Optional, MusicKit / System Music Player)

    private var mediaWidgetBar: some View {
        HStack(spacing: 12) {
            Group {
                if let artwork = media.nowPlaying?.artworkImage {
                    Image(uiImage: artwork)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(SpeedometerStyle.accent.opacity(0.14))
                        Image(systemName: "music.note")
                            .modifier(AdaptiveFont(size: 16, weight: .semibold))
                            .foregroundStyle(SpeedometerStyle.accent)
                    }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                switch media.availability {
                case .ready:
                    Text(media.nowPlaying?.title ?? "Apple Music")
                        .modifier(AdaptiveFont(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                        .lineLimit(1)
                    Text(media.nowPlaying?.artist ?? "")
                        .modifier(AdaptiveFont(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                        .lineLimit(1)
                case .authorizationRequired:
                    Text("Apple Music")
                        .modifier(AdaptiveFont(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                    Text("Tap Connect to control playback")
                        .modifier(AdaptiveFont(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                        .lineLimit(1)
                case .denied:
                    Text("Music access is off")
                        .modifier(AdaptiveFont(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                    Text("Enable Media & Apple Music in Settings")
                        .modifier(AdaptiveFont(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                        .lineLimit(1)
                case .empty:
                    Text("Nothing playing")
                        .modifier(AdaptiveFont(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.foreground)
                    Text("Start playback in Apple Music")
                        .modifier(AdaptiveFont(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            switch media.availability {
            case .ready:
                HStack(spacing: 4) {
                    mediaControlButton(symbol: "backward.fill", label: "Previous track") {
                        media.skipToPrevious()
                    }
                    mediaControlButton(
                        symbol: media.nowPlaying?.isPlaying == true ? "pause.fill" : "play.fill",
                        label: media.nowPlaying?.isPlaying == true ? "Pause music" : "Play music"
                    ) {
                        media.togglePlayPause()
                    }
                    mediaControlButton(symbol: "forward.fill", label: "Next track") {
                        media.skipToNext()
                    }
                }
            case .authorizationRequired:
                Button("Connect") {
                    media.requestAuthorization()
                }
                .modifier(AdaptiveFont(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(SpeedometerStyle.accentForeground)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(SpeedometerStyle.accent, in: Capsule())
            case .denied:
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .modifier(AdaptiveFont(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(SpeedometerStyle.accent)
                .padding(.horizontal, 12)
                .frame(minHeight: 36)
                .background(SpeedometerStyle.accent.opacity(0.14), in: Capsule())
            case .empty:
                EmptyView()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .veluraGlassCard(cornerRadius: 20, stroke: SpeedometerStyle.foreground.opacity(0.1))
    }

    private func mediaControlButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .modifier(AdaptiveFont(size: 15, weight: .semibold))
                .foregroundStyle(SpeedometerStyle.foreground)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(VeluraGlassPressButtonStyle())
        .accessibilityLabel(label)
    }

    // MARK: - Bottom Action Controls

    private func bottomControlBar(isLandscape: Bool) -> some View {
        GlassEffectContainer(spacing: 10) {
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
                    HStack(spacing: 10) {
                        Image(systemName: model.isSessionActive ? "pause.fill" : "play.fill")
                            .modifier(AdaptiveFont(size: 17, weight: .bold))
                            .foregroundStyle(SpeedometerStyle.accent)
                            .contentTransition(.symbolEffect(.replace))
                        Text(model.isSessionActive ? "Pause" : (model.hasUnfinishedSession ? "Resume" : "Start drive"))
                            .modifier(AdaptiveFont(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(SpeedometerStyle.foreground)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: isLandscape ? 50 : 56)
                    .contentShape(Capsule())
                    .veluraGlassCapsule(
                        tint: SpeedometerStyle.accent.opacity(0.24),
                        interactive: true
                    )
                    .glassEffectID("cockpit-primary-action", in: cockpitActionsNamespace)
                }
                .buttonStyle(VeluraGlassPressButtonStyle())
                .disabled(model.isDriveStorageLoading || model.isFinishingSession)

                if model.hasUnfinishedSession {
                    Button {
                        showingEndConfirmation = true
                    } label: {
                        Label("Finish", systemImage: "stop.fill")
                            .modifier(AdaptiveFont(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(SpeedometerStyle.warning)
                            .padding(.horizontal, 20)
                            .frame(minHeight: isLandscape ? 50 : 56)
                            .contentShape(Capsule())
                            .veluraGlassCapsule(
                                tint: SpeedometerStyle.warning.opacity(0.18),
                                interactive: true
                            )
                            .glassEffectID("cockpit-finish-action", in: cockpitActionsNamespace)
                    }
                    .buttonStyle(VeluraGlassPressButtonStyle())
                    .disabled(model.isFinishingSession)
                    .transition(VeluraMotion.transition(.scale(scale: 0.92).combined(with: .opacity), reduceMotion: reduceMotion))
                }
            }
        }
        .animation(VeluraMotion.animation(VeluraMotion.morph, reduceMotion: reduceMotion), value: model.hasUnfinishedSession)
    }

    // MARK: - External Navigation (Apple Maps)

    private var externalNavigationSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Enter a destination to open turn-by-turn directions in Apple Maps. Velura continues recording your drive in the background.")
                    .modifier(AdaptiveFont(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)

                TextField("Address, place or city (optional)", text: $destinationDraft)
                    .modifier(AdaptiveFont(size: 15, weight: .medium, design: .rounded))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .veluraGlassCard(cornerRadius: 16)
                    .submitLabel(.go)
                    .onSubmit {
                        launchExternalMaps()
                    }

                Button(action: launchExternalMaps) {
                    Label(
                        destinationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "Open Apple Maps"
                            : "Directions in Apple Maps",
                        systemImage: "arrow.triangle.turn.up.right.diamond.fill"
                    )
                    .modifier(AdaptiveFont(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.accentForeground)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(SpeedometerStyle.accent, in: Capsule())
                }
                .buttonStyle(VeluraGlassPressButtonStyle())

                Spacer()
            }
            .padding(20)
            .background(VeluraAmbientBackdrop(intensity: 0.14))
            .navigationTitle("Apple Maps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showingDestinationSheet = false }
                }
            }
        }
        .preferredColorScheme(appearance.preferredColorScheme)
    }

    private func launchExternalMaps() {
        let trimmed = destinationDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        savedDestination = trimmed
        showingDestinationSheet = false
        openAppleMaps(destination: trimmed)
    }

    private func openAppleMaps(destination: String) {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        var components = URLComponents(string: "maps://")
        if !trimmed.isEmpty {
            components?.queryItems = [
                URLQueryItem(name: "daddr", value: trimmed),
                URLQueryItem(name: "dirflg", value: "d")
            ]
        }
        guard let url = components?.url else { return }
        openURL(url)
    }

    // MARK: - Helpers

    private var driveStateBanner: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(driveStateColor)
                .frame(width: 8, height: 8)
            Text(model.driveState.badgeTitle)
                .modifier(AdaptiveFont(size: 11, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(SpeedometerStyle.foreground)
            Spacer()
            Text(model.gpsStatusDetail)
                .modifier(AdaptiveFont(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(SpeedometerStyle.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .veluraGlassCapsule()
    }

    private func cockpitMetricTile(title: String, value: String, accent: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .modifier(AdaptiveFont(size: 10, weight: .bold, design: .rounded))
                .tracking(0.9)
                .foregroundStyle(SpeedometerStyle.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .modifier(AdaptiveFont(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(accent ?? SpeedometerStyle.foreground)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .veluraGlassCard(cornerRadius: 20, stroke: SpeedometerStyle.foreground.opacity(0.1))
        .accessibilityElement(children: .combine)
    }

    private func compactStripMetric(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .modifier(AdaptiveFont(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(SpeedometerStyle.foreground)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .modifier(AdaptiveFont(size: 9, weight: .bold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(SpeedometerStyle.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private func cockpitDuration(_ duration: TimeInterval) -> String {
    let totalSeconds = max(0, Int(duration))
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%02d:%02d", minutes, seconds)
}
