import SwiftUI
import UIKit

// App-wide palettes and dial options. The observable settings object persists choices
// so every screen can react to the same appearance state.
enum AppearanceTheme: String, CaseIterable, Identifiable {
    case midnight
    case ocean
    case graphite
    case forest
    case ember

    var id: String { rawValue }

    var title: String {
        switch self {
        case .midnight: "Midnight"
        case .ocean: "Ocean"
        case .graphite: "Graphite"
        case .forest: "Forest"
        case .ember: "Ember"
        }
    }

    var background: Color {
        switch self {
        case .midnight: Color(red: 0.025, green: 0.043, blue: 0.067)
        case .ocean: Color(red: 0.018, green: 0.070, blue: 0.078)
        case .graphite: Color(red: 0.055, green: 0.058, blue: 0.067)
        case .forest: Color(red: 0.027, green: 0.078, blue: 0.059)
        case .ember: Color(red: 0.078, green: 0.067, blue: 0.063)
        }
    }

    var secondary: Color {
        switch self {
        case .midnight: Color(red: 0.63, green: 0.70, blue: 0.77)
        case .ocean: Color(red: 0.66, green: 0.77, blue: 0.75)
        case .graphite: Color(red: 0.72, green: 0.73, blue: 0.76)
        case .forest: Color(red: 0.66, green: 0.76, blue: 0.69)
        case .ember: Color(red: 0.76, green: 0.70, blue: 0.63)
        }
    }

    var accent: Color {
        switch self {
        case .midnight: Color(red: 0.27, green: 0.79, blue: 0.98)
        case .ocean: Color(red: 0.24, green: 0.86, blue: 0.75)
        case .graphite: Color(red: 1.0, green: 0.69, blue: 0.28)
        case .forest: Color(red: 0.30, green: 0.82, blue: 0.52)
        case .ember: Color(red: 0.83, green: 0.48, blue: 0.27)
        }
    }

    var mint: Color {
        switch self {
        case .midnight: Color(red: 0.34, green: 0.91, blue: 0.73)
        case .ocean: Color(red: 0.48, green: 0.92, blue: 0.70)
        case .graphite: Color(red: 0.52, green: 0.88, blue: 0.65)
        case .forest: Color(red: 0.70, green: 0.88, blue: 0.58)
        case .ember: Color(red: 0.48, green: 0.79, blue: 0.67)
        }
    }

    var foreground: Color {
        switch self {
        case .midnight, .ocean, .graphite: .white
        case .forest: Color(red: 0.92, green: 0.96, blue: 0.93)
        case .ember: Color(red: 0.96, green: 0.93, blue: 0.87)
        }
    }

    var accentForeground: Color {
        switch self {
        case .midnight: .white
        case .ocean: Color(red: 0.015, green: 0.14, blue: 0.13)
        case .graphite: Color(red: 0.15, green: 0.10, blue: 0.025)
        case .forest: Color(red: 0.035, green: 0.16, blue: 0.095)
        case .ember: Color(red: 0.16, green: 0.085, blue: 0.045)
        }
    }

    var colorScheme: ColorScheme { .dark }

    func foreground(on color: Color) -> Color {
        contrastingForeground(for: color)
    }

    var warning: Color { Color(red: 1.0, green: 0.34, blue: 0.31) }
}

enum SpeedometerDialStyle: String, CaseIterable, Identifiable {
    case classic
    case minimal
    case sport
    case segmentedLED
    case digitalHUD
    case twinRing
    case fullCircle
    case verticalBar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .minimal: "Minimal"
        case .sport: "Sport"
        case .segmentedLED: "LED arc"
        case .digitalHUD: "Digital HUD"
        case .twinRing: "Twin ring"
        case .fullCircle: "Full circle"
        case .verticalBar: "Vertical bar"
        }
    }

    var trackWidth: CGFloat {
        switch self {
        case .classic: 10
        case .minimal: 7
        case .sport: 13
        case .segmentedLED: 8
        case .digitalHUD: 8
        case .twinRing: 8
        case .fullCircle: 10
        case .verticalBar: 8
        }
    }

    var tickCount: Int {
        switch self {
        case .classic: 40
        case .minimal: 12
        case .sport: 64
        case .segmentedLED: 48
        case .digitalHUD, .twinRing, .fullCircle, .verticalBar: 0
        }
    }

    var majorTickInterval: Int {
        switch self {
        case .classic: 10
        case .minimal: 6
        case .sport, .segmentedLED: 8
        case .digitalHUD, .twinRing, .fullCircle, .verticalBar: 1
        }
    }

    var labelCount: Int {
        switch self {
        case .classic, .sport: 5
        case .minimal, .segmentedLED, .twinRing: 3
        case .digitalHUD, .fullCircle, .verticalBar: 0
        }
    }

    var showsTicks: Bool {
        switch self {
        case .classic, .sport: true
        case .minimal, .segmentedLED, .digitalHUD, .twinRing, .fullCircle, .verticalBar: false
        }
    }
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case palette
    case light
    case dark
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .palette: "Palette"
        case .light: "Light"
        case .dark: "Dark"
        case .system: "System"
        }
    }
}

final class AppAppearance: ObservableObject {
    static let shared = AppAppearance()

    @Published var theme: AppearanceTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.themeStorageKey) }
    }

    @Published var appearanceMode: AppAppearanceMode {
        didSet { UserDefaults.standard.set(appearanceMode.rawValue, forKey: Self.appearanceModeStorageKey) }
    }

    @Published var dialStyle: SpeedometerDialStyle {
        didSet { UserDefaults.standard.set(dialStyle.rawValue, forKey: Self.dialStorageKey) }
    }

    private static let themeStorageKey = "speedometer.appearance.theme"
    private static let appearanceModeStorageKey = "speedometer.appearance.mode"
    private static let dialStorageKey = "speedometer.appearance.dialStyle"
    private static let legacyCustomColorsStorageKey = "speedometer.appearance.customColors"

    private init() {
        let defaults = UserDefaults.standard
        let savedTheme = defaults.string(forKey: Self.themeStorageKey)
        let savedAppearanceMode = AppAppearanceMode(rawValue: defaults.string(forKey: Self.appearanceModeStorageKey) ?? "") ?? .palette
        let restoredAppearanceMode = savedTheme == "daylight" && savedAppearanceMode == .palette
            ? AppAppearanceMode.light
            : savedAppearanceMode

        if savedTheme == "custom" {
            defaults.set(AppearanceTheme.midnight.rawValue, forKey: Self.themeStorageKey)
            theme = .midnight
        } else if savedTheme == "daylight" {
            defaults.set(AppearanceTheme.midnight.rawValue, forKey: Self.themeStorageKey)
            theme = .midnight
        } else {
            theme = AppearanceTheme(rawValue: savedTheme ?? "") ?? .midnight
        }

        appearanceMode = restoredAppearanceMode
        if savedTheme == "daylight" {
            defaults.set(restoredAppearanceMode.rawValue, forKey: Self.appearanceModeStorageKey)
        }
        dialStyle = SpeedometerDialStyle(rawValue: defaults.string(forKey: Self.dialStorageKey) ?? "") ?? .classic
        defaults.removeObject(forKey: Self.legacyCustomColorsStorageKey)
    }

    var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case .palette: theme.colorScheme
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }

    var background: Color {
        switch appearanceMode {
        case .palette: theme.background
        case .light: .white
        case .dark: Color(red: 0.035, green: 0.039, blue: 0.047)
        case .system: Color(uiColor: .systemBackground)
        }
    }

    var foreground: Color {
        switch appearanceMode {
        case .palette: theme.foreground
        case .light: Color(red: 0.10, green: 0.12, blue: 0.15)
        case .dark: .white
        case .system: .primary
        }
    }

    var secondary: Color {
        switch appearanceMode {
        case .palette: theme.secondary
        case .light: Color(red: 0.34, green: 0.37, blue: 0.41)
        case .dark: Color(red: 0.66, green: 0.69, blue: 0.73)
        case .system: .secondary
        }
    }

    var accent: Color {
        switch appearanceMode {
        case .palette: theme.accent
        case .light: Color(red: 0.10, green: 0.38, blue: 0.75)
        case .dark: Color(red: 0.29, green: 0.57, blue: 0.98)
        case .system: Color(uiColor: .systemBlue)
        }
    }

    var accentForeground: Color {
        switch appearanceMode {
        case .palette: theme.accentForeground
        case .light, .dark, .system: .white
        }
    }

    var mint: Color {
        switch appearanceMode {
        case .palette: theme.mint
        case .light: Color(red: 0.10, green: 0.46, blue: 0.33)
        case .dark: Color(red: 0.32, green: 0.84, blue: 0.63)
        case .system: Color(uiColor: .systemGreen)
        }
    }

    var warning: Color {
        switch appearanceMode {
        case .palette: theme.warning
        case .light: Color(red: 0.72, green: 0.16, blue: 0.13)
        case .dark: Color(red: 1.0, green: 0.36, blue: 0.33)
        case .system: Color(uiColor: .systemRed)
        }
    }
}

private func relativeLuminance(of color: Color) -> Double {
    let uiColor = UIColor(color)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var opacity: CGFloat = 0
    guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &opacity) else { return 0 }

    func linearized(_ component: Double) -> Double {
        component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }

    return 0.2126 * linearized(Double(red))
        + 0.7152 * linearized(Double(green))
        + 0.0722 * linearized(Double(blue))
}

private func contrastingForeground(for color: Color) -> Color {
    let luminance = relativeLuminance(of: color)
    let whiteContrast = 1.05 / (luminance + 0.05)
    let blackContrast = (luminance + 0.05) / 0.05
    return whiteContrast >= blackContrast ? .white : .black
}
