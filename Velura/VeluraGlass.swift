import SwiftUI

// Shared Liquid Glass primitives for Velura (iOS 26+).
//
// Rules this file encodes:
// • Native `Glass` only. No hand-added strokes, shadows or opacity on a glass
//   surface — the system owns edge treatment, specular highlights and the
//   Reduce Transparency / Increase Contrast adaptation. Re-frosting glass by hand
//   duplicates (and fights) what the material already does.
// • `glassEffect` is applied last, after layout and appearance modifiers.
// • Two glass surfaces near each other belong to one `GlassEffectContainer`
//   (the container is what makes them sample and blend as one body).
// • Glass is for the control layer. Content (metrics, lists, text) uses
//   `veluraContentCard` — a plain vibrancy fill with no sampling cost.

// MARK: - Backdrop

/// The thing glass refracts. A flat single-colour background makes glass read as a
/// tinted rectangle, so every screen keeps this living gradient underneath.
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

    private var isLightSurface: Bool {
        appearance.appearanceMode == .light
    }

    var body: some View {
        ZStack {
            SpeedometerStyle.background

            // A soft diagonal wash keeps depth even when transparency is reduced,
            // so floating chrome never sits on a dead flat field.
            LinearGradient(
                colors: [
                    primaryGlow.opacity(isLightSurface ? 0.05 : 0.10),
                    .clear,
                    secondaryGlow.opacity(isLightSurface ? 0.04 : 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if !reduceTransparency {
                GeometryReader { proxy in
                    let size = proxy.size
                    let maxDim = max(size.width, size.height)
                    let primaryAlpha = (isLightSurface ? 0.14 : 0.22) + clampedIntensity * 0.14
                    let secondaryAlpha = (isLightSurface ? 0.09 : 0.14) + (isActive ? 0.06 : 0)

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

// MARK: - Glass

struct VeluraGlassSurfaceModifier<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool

    func body(content: Content) -> some View {
        content.glassEffect(resolvedGlass, in: shape)
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

// MARK: - Content surface (deliberately not glass)

/// Fill for the content layer. Content does not sample: a scrolling card with a live
/// glass region per row multiplies GPU cost per visible row and reads as chrome.
struct VeluraContentSurfaceModifier<S: InsettableShape>: ViewModifier {
    @ObservedObject private var appearance = AppAppearance.shared
    let shape: S
    let emphasized: Bool

    func body(content: Content) -> some View {
        content
            .background { shape.fill(fill) }
            .overlay {
                shape.strokeBorder(
                    SpeedometerStyle.foreground.opacity(appearance.appearanceMode == .light ? 0.08 : 0.06),
                    lineWidth: 0.5
                )
            }
    }

    private var fill: Color {
        switch appearance.appearanceMode {
        case .light:
            Color(red: 0.99, green: 0.99, blue: 1.0).opacity(emphasized ? 1 : 0.82)
        case .system:
            Color(uiColor: .secondarySystemBackground)
        case .palette, .dark:
            SpeedometerStyle.foreground.opacity(emphasized ? 0.11 : 0.065)
        }
    }
}

extension View {
    /// Floating control surface — glass.
    func veluraGlassCard(
        cornerRadius: CGFloat = 24,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(
            VeluraGlassSurfaceModifier(
                shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                tint: tint,
                interactive: interactive
            )
        )
    }

    /// Floating control surface — glass capsule.
    func veluraGlassCapsule(
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(
            VeluraGlassSurfaceModifier(
                shape: Capsule(),
                tint: tint,
                interactive: interactive
            )
        )
    }

    /// Floating control surface — glass circle (icon buttons).
    func veluraGlassCircle(
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(
            VeluraGlassSurfaceModifier(
                shape: Circle(),
                tint: tint,
                interactive: interactive
            )
        )
    }

    /// Content-layer card. Same silhouette as the glass cards, no sampling.
    func veluraContentCard(cornerRadius: CGFloat = 22, emphasized: Bool = false) -> some View {
        modifier(
            VeluraContentSurfaceModifier(
                shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                emphasized: emphasized
            )
        )
    }

    /// Content-layer status capsule (GPS state, badges). Not glass — it does not float.
    func veluraContentCapsule(emphasized: Bool = false) -> some View {
        modifier(
            VeluraContentSurfaceModifier(
                shape: Capsule(),
                emphasized: emphasized
            )
        )
    }
}

// MARK: - Press feedback

/// Press feedback for custom-shaped controls. Kept separate from glass so the
/// material stays untouched: only the label scales, the sampling surface does not.
struct VeluraGlassPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var pressedScale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Scale only. A partial-opacity fade on a glass ancestor collapses the
            // refraction, so pressed state never touches alpha.
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(
                VeluraMotion.animation(VeluraMotion.press, reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}

// MARK: - Grouping

/// Wraps adjacent floating glass controls so they sample, blend and can morph as one
/// body. Use around every cluster of two or more glass surfaces.
struct VeluraGlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content
        }
    }
}

// MARK: - Floating header

/// Glass header for screens that hide the navigation bar (map cockpits, route review).
/// Screens with a real navigation bar should use it instead — the system already
/// provides glass there.
struct VeluraFloatingHeader<Content: View>: View {
    var cornerRadius: CGFloat = 26
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) { content }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .veluraGlassCard(cornerRadius: cornerRadius)
    }
}
