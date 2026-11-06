import CoreLocation
import SwiftUI
import UIKit

struct FirstLaunchSetupView: View {
    @ObservedObject var model: SpeedometerModel
    let onContinue: () -> Void

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    private let background = Color(red: 0.012, green: 0.035, blue: 0.060)
    private let cyan = Color(red: 0.22, green: 0.83, blue: 0.98)
    private let secondary = Color(red: 0.66, green: 0.75, blue: 0.84)

    private var isLocationAuthorized: Bool {
        model.authorizationStatus == .authorizedAlways || model.authorizationStatus == .authorizedWhenInUse
    }

    private var needsSettings: Bool {
        model.authorizationStatus == .denied || model.authorizationStatus == .restricted
    }

    private var locationTitle: String {
        switch model.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            "Location is enabled"
        case .denied:
            "Location access is off"
        case .restricted:
            "Location access is restricted"
        case .notDetermined:
            "Needed for live speed, trip distance and recorded routes."
        @unknown default:
            "Location access is unavailable"
        }
    }

    private var locationDetail: String? {
        switch model.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            "Live speed and trip details are ready. Location is used while a drive is active."
        case .denied:
            "Open Settings to enable live speed, trip distance and recorded routes."
        case .restricted:
            "Location is restricted on this device. You can continue without it."
        case .notDetermined:
            nil
        @unknown default:
            "You can continue without location and change access later in Settings."
        }
    }

    private var primaryActionTitle: String {
        if isLocationAuthorized { return "Continue" }
        if needsSettings { return "Open Settings" }
        return "Enable location"
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            LinearGradient(
                colors: [Color(red: 0.018, green: 0.085, blue: 0.13), background.opacity(0.15), background],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(cyan.opacity(0.09))
                .frame(width: 270, height: 270)
                .blur(radius: 90)
                .offset(x: 150, y: -360)
                .accessibilityHidden(true)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    brandMark
                    welcomeHeader
                    featureCard(
                        symbol: "speedometer",
                        title: "Live speed",
                        detail: "Measure speed from GPS during an active drive."
                    )
                    featureCard(
                        symbol: "point.3.connected.trianglepath.dotted",
                        title: "Trip details",
                        detail: "Save distance, top speed and route on this device."
                    )
                    featureCard(
                        symbol: "shield",
                        title: "Your privacy",
                        detail: "Location is accessed only while a drive is active."
                    )
                    locationAccessCard
                    Text("You can change location access anytime in Settings.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 1)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared || reduceMotion ? 0 : 14)
                .animation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion), value: hasAppeared)
            }
        }
        .preferredColorScheme(.dark)
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.authorizationStatus)
        .onAppear {
            model.refreshLocationAuthorizationStatus()
            withAnimation(VeluraMotion.animation(VeluraMotion.content, reduceMotion: reduceMotion)) {
                hasAppeared = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refreshLocationAuthorizationStatus()
            }
        }
    }

    private var brandMark: some View {
        VStack(spacing: 6) {
            OnboardingSpeedometerMark()
                .stroke(cyan, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: 36, height: 28)
                .shadow(color: cyan.opacity(0.42), radius: 10)
                .accessibilityHidden(true)
            Text("VELURA")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .tracking(6)
                .foregroundStyle(.white.opacity(0.94))
                .padding(.leading, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Velura")
    }

    private var welcomeHeader: some View {
        VStack(spacing: 6) {
            Text("GETTING STARTED")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(secondary)
            Text("Welcome to Velura")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .tracking(-0.6)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.78)
                .lineLimit(1)
            Text("Set up your speedometer in seconds.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 0)
        .accessibilityElement(children: .combine)
    }

    private func featureCard(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(cyan.opacity(0.08))
                Image(systemName: symbol)
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(cyan)
                    .shadow(color: cyan.opacity(0.28), radius: 9)
            }
            .frame(width: 56, height: 56)
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(cyan.opacity(0.12), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 23))
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(.white.opacity(0.075), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var locationAccessCard: some View {
        VStack(spacing: 9) {
            Text("LOCATION ACCESS")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(secondary)

            ZStack {
                Circle().stroke(cyan.opacity(0.05), lineWidth: 1).frame(width: 84, height: 84)
                Circle().stroke(cyan.opacity(0.08), lineWidth: 1).frame(width: 68, height: 68)
                Circle()
                    .fill(cyan.opacity(0.08))
                    .frame(width: 54, height: 54)
                    .overlay {
                        Circle().stroke(cyan.opacity(0.16), lineWidth: 1)
                    }
                Image(systemName: needsSettings ? "location.slash" : "location")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(cyan)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityHidden(true)

            VStack(spacing: 5) {
                if let locationDetail {
                    Text(locationTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(locationDetail)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(secondary)
                } else {
                    Text(locationTitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(secondary)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 44)

            Button(action: handlePrimaryAction) {
                Text(primaryActionTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.015, green: 0.10, blue: 0.15))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(colors: [Color(red: 0.31, green: 0.91, blue: 1), cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule()
                    )
                    .shadow(color: cyan.opacity(0.25), radius: 14, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityHint(primaryActionHint)

            Button(action: onContinue) {
                Text("Continue without location")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.68, green: 0.79, blue: 0.88))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(.white.opacity(0.025), in: Capsule())
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .overlay {
                        Capsule().stroke(.white.opacity(0.08), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 25))
        .overlay {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .stroke(cyan.opacity(0.13), lineWidth: 1)
        }
        .animation(VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion), value: model.authorizationStatus)
        .accessibilityElement(children: .contain)
    }

    private var primaryActionHint: String {
        if isLocationAuthorized { return "Continue to Velura" }
        if needsSettings { return "Open iOS Settings to change location access" }
        return "Requests permission to use location while a drive is active"
    }

    private func handlePrimaryAction() {
        if isLocationAuthorized {
            onContinue()
        } else if needsSettings {
            guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
            openURL(settingsURL)
        } else {
            model.requestLocationAuthorization()
        }
    }
}

private struct OnboardingSpeedometerMark: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.22)
        let radius = min(rect.width, rect.height) * 0.44
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(200),
            endAngle: .degrees(340),
            clockwise: false
        )
        let angle = -CGFloat.pi / 3
        let tip = CGPoint(x: center.x + cos(angle) * radius * 0.64, y: center.y + sin(angle) * radius * 0.64)
        path.move(to: center)
        path.addLine(to: tip)
        return path
    }
}
