import SwiftUI

// Shared Liquid Glass design primitives for Velura (iOS 26+).
// Respects Reduce Transparency, Reduce Motion, and Light/Dark/Palette appearance modes.

struct VeluraAmbientBackdrop: View {
    @ObservedObject private var appearance = AppAppearance.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var intensity: Double = 0
    var isWarning: Bool = false
    var isActive: Bool = false

    private var clampedIntensity: Double {
        min(max(intensity, 0), 1)
    }

    private var primaryGlow: Color {
        isWarning ? SpeedometerStyle.warning : SpeedometerStyle.accent
    }

    private var secondaryGlow: Color {
        isWarning ? SpeedometerStyle.warning.opacity(0.65) : SpeedometerStyle.mint
    }

    var body: some View {
        ZStack {
            SpeedometerStyle.background

            if !reduceTransparency {
                GeometryReader { proxy in
                    let size = proxy.size
                    let maxDim = max(size.width, size.height)
                    let primaryAlpha = (appearance.appearanceMode == .light ? 0.14 : 0.22) + clampedIntensity * 0.14
                    let secondaryAlpha = (appearance.appearanceMode == .light ? 0.09 : 0.14) + (isActive ? 0.06 : 0)

                    ZStack {
                        RadialGradient(
                            colors: [
                                primaryGlow.opacity(primaryAlpha),
                                primaryGlow.opacity(primaryAlpha * 0.35),
                                .clear
                            ],
                            center: .center,
                            startRadius: 12,
                            endRadius: maxDim * (0.48 + clampedIntensity * 0.12)
                        )
                        .frame(width: maxDim * 1.15, height: maxDim * 1.15)
                        .position(
                            x: size.width * (0.24 + clampedIntensity * 0.14),
                            y: size.height * (0.16 + clampedIntensity * 0.06)
                        )

                        RadialGradient(
                            colors: [
                                secondaryGlow.opacity(secondaryAlpha),
                                secondaryGlow.opacity(secondaryAlpha * 0.25),
                                .clear
                            ],
                            center: .center,
                            startRadius: 8,
                            endRadius: maxDim * 0.52
                        )
                        .frame(width: maxDim, height: maxDim)
                        .position(
                            x: size.width * 0.84,
                            y: size.height * (0.76 - clampedIntensity * 0.08)
                        )

                        if isWarning {
                            LinearGradient(
                                colors: [
                                    SpeedometerStyle.warning.opacity(0.18),
                                    .clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        }
                    }
                    .animation(
                        VeluraMotion.animation(VeluraMotion.ambient, reduceMotion: reduceMotion),
                        value: clampedIntensity
                    )
                    .animation(
                        VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion),
                        value: isWarning
                    )
                    .animation(
                        VeluraMotion.animation(VeluraMotion.stateChange, reduceMotion: reduceMotion),
                        value: isActive
                    )
                }
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct VeluraGlassSurfaceModifier<S: Shape>: ViewModifier {
    @ObservedObject private var appearance = AppAppearance.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let shape: S
    let tint: Color?
    let interactive: Bool
    let strokeColor: Color?

    private var opaqueFallbackFill: Color {
        switch appearance.appearanceMode {
        case .light:
            Color(red: 0.94, green: 0.95, blue: 0.97)
        case .system:
            Color(uiColor: .secondarySystemBackground)
        case .palette, .dark:
            SpeedometerStyle.background.opacity(0.96)
        }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(opaqueFallbackFill, in: shape)
                .overlay {
                    if let tint {
                        shape.fill(tint.opacity(0.22))
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    shape.stroke(
                        strokeColor ?? SpeedometerStyle.foreground.opacity(0.18),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
                }
        } else {
            content
                .glassEffect(resolvedGlass, in: shape)
                .overlay {
                    if let strokeColor {
                        shape.stroke(strokeColor, lineWidth: 0.75)
                            .allowsHitTesting(false)
                    }
                }
        }
    }

    private var resolvedGlass: Glass {
        var glass: Glass = .regular
        if let tint {
            glass = glass.tint(tint)
        }
        if interactive {
            glass = glass.interactive()
        }
        return glass
    }
}

extension View {
    func veluraGlassCard(
        cornerRadius: CGFloat = 24,
        tint: Color? = nil,
        interactive: Bool = false,
        stroke: Color? = nil
    ) -> some View {
        modifier(
            VeluraGlassSurfaceModifier(
                shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                tint: tint,
                interactive: interactive,
                strokeColor: stroke
            )
        )
    }

    func veluraGlassCapsule(
        tint: Color? = nil,
        interactive: Bool = false,
        stroke: Color? = nil
    ) -> some View {
        modifier(
            VeluraGlassSurfaceModifier(
                shape: Capsule(),
                tint: tint,
                interactive: interactive,
                strokeColor: stroke
            )
        )
    }

    func veluraGlassCircle(
        tint: Color? = nil,
        interactive: Bool = false,
        stroke: Color? = nil
    ) -> some View {
        modifier(
            VeluraGlassSurfaceModifier(
                shape: Circle(),
                tint: tint,
                interactive: interactive,
                strokeColor: stroke
            )
        )
    }
}

struct VeluraGlassPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var pressedScale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(
                VeluraMotion.animation(VeluraMotion.press, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}
