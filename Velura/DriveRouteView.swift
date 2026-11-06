import MapKit
import SwiftUI

struct DriveRouteView: View {
    let drive: DriveRecord
    let onDeleteRoute: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("speedometer.usesMiles") private var usesMiles = false
    @State private var routeCoordinates: [DriveRoutePoint]
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showingDeleteConfirmation = false

    init(drive: DriveRecord, onDeleteRoute: @escaping () -> Void) {
        self.drive = drive
        self.onDeleteRoute = onDeleteRoute
        _routeCoordinates = State(initialValue: drive.routeCoordinates)
    }

    private var coordinates: [CLLocationCoordinate2D] {
        routeCoordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
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
        ZStack {
            SpeedometerStyle.background.ignoresSafeArea()

            if routeCoordinates.count >= 2 {
                routeMap
            } else {
                emptyMapState
            }

            VStack(spacing: 0) {
                header

                if routeCoordinates.count >= 2 {
                    Text(dateChipText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.top, 16)
                }

                Spacer(minLength: 14)
                summaryCard
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("Delete this route?", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete route", role: .destructive) {
                onDeleteRoute()
                withAnimation(.smooth(duration: 0.35)) {
                    routeCoordinates.removeAll()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The route will be removed from this device. Drive statistics will be kept.")
        }
    }

    private var routeMap: some View {
        Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
            MapPolyline(coordinates: coordinates)
                .stroke(SpeedometerStyle.accent, lineWidth: 5)

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
                .stroke(.white.opacity(0.035), lineWidth: 1)
                .frame(width: 300, height: 300)
            Circle()
                .stroke(.white.opacity(0.025), lineWidth: 1)
                .frame(width: 430, height: 430)

            VStack(spacing: 11) {
                Image(systemName: "map")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(SpeedometerStyle.accent)
                Text("No route recorded")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("A route will appear here when GPS locations were recorded during this drive.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(SpeedometerStyle.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 270)
            }
            .padding(24)
            .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to drive details")

            Spacer()

            Text("Drive route")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Color.clear
                .frame(width: 42, height: 42)
                .accessibilityHidden(true)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(String(format: "%.1f", displayedDistance)) \(distanceUnit)")
                    .font(.system(size: 38, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text("DISTANCE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(SpeedometerStyle.secondary)
            }

            Rectangle()
                .fill(.white.opacity(0.11))
                .frame(height: 1)

            HStack(spacing: 0) {
                summaryMetric(title: "TOP SPEED", value: "\(Int(displayedTopSpeed.rounded())) \(speedUnit)")
                Rectangle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 1, height: 38)
                summaryMetric(title: "DURATION", value: routeDuration(drive.duration))
            }

            if routeCoordinates.count >= 2 {
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete route", systemImage: "trash")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(SpeedometerStyle.warning)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .glassEffect(.regular.tint(SpeedometerStyle.warning.opacity(0.12)), in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Deletes the route only; drive statistics are kept")
            }
        }
        .padding(18)
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 25))
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(SpeedometerStyle.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
                    .fill(.white)
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
