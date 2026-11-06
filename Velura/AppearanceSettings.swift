import SwiftUI
import UIKit

// App-wide palettes and dial options. The observable settings object persists choices
// so every screen can react to the same appearance state.
enum AppearanceTheme: String, CaseIterable, Identifiable {
    case midnight
    case ocean
    case graphite
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .midnight: "Midnight"
        case .ocean: "Ocean"
        case .graphite: "Graphite"
        case .custom: "Custom"
        }
    }

    var background: Color {
        switch self {
        case .midnight: Color(red: 0.025, green: 0.043, blue: 0.067)
        case .ocean: Color(red: 0.018, green: 0.070, blue: 0.078)
        case .graphite: Color(red: 0.055, green: 0.058, blue: 0.067)
        case .custom: AppAppearance.shared.customBackgroundColor
        }
    }

    var secondary: Color {
        switch self {
        case .midnight: Color(red: 0.63, green: 0.70, blue: 0.77)
        case .ocean: Color(red: 0.66, green: 0.77, blue: 0.75)
        case .graphite: Color(red: 0.72, green: 0.73, blue: 0.76)
        case .custom: secondaryTextColor(on: background)
        }
    }

    var accent: Color {
        switch self {
        case .midnight: Color(red: 0.27, green: 0.79, blue: 0.98)
        case .ocean: Color(red: 0.24, green: 0.86, blue: 0.75)
        case .graphite: Color(red: 1.0, green: 0.69, blue: 0.28)
        case .custom: AppAppearance.shared.customAccentColor
        }
    }

    var mint: Color {
        switch self {
        case .midnight: Color(red: 0.34, green: 0.91, blue: 0.73)
        case .ocean: Color(red: 0.48, green: 0.92, blue: 0.70)
        case .graphite: Color(red: 0.52, green: 0.88, blue: 0.65)
        case .custom: AppAppearance.shared.customPositiveColor
        }
    }

    var foreground: Color {
        self == .custom ? contrastingForeground(for: background) : .white
    }

    var accentForeground: Color {
        switch self {
        case .midnight: .white
        case .ocean: Color(red: 0.015, green: 0.14, blue: 0.13)
        case .graphite: Color(red: 0.15, green: 0.10, blue: 0.025)
        case .custom: contrastingForeground(for: accent)
        }
    }

    var colorScheme: ColorScheme {
        self == .custom && relativeLuminance(of: background) > 0.179 ? .light : .dark
    }

    func foreground(on color: Color) -> Color {
        contrastingForeground(for: color)
    }

    var warning: Color { Color(red: 1.0, green: 0.34, blue: 0.31) }
}

enum SpeedometerDialStyle: String, CaseIterable, Identifiable {
    case classic
    case minimal
    case sport
    case analog
    case segmentedLED
    case digitalHUD
    case twinRing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .minimal: "Minimal"
        case .sport: "Sport"
        case .analog: "Analog"
        case .segmentedLED: "LED arc"
        case .digitalHUD: "Digital HUD"
        case .twinRing: "Twin ring"
        }
    }

    var trackWidth: CGFloat {
        switch self {
        case .classic: 10
        case .minimal: 7
        case .sport: 13
        case .analog: 7
        case .segmentedLED: 8
        case .digitalHUD: 8
        case .twinRing: 8
        }
    }

    var tickCount: Int {
        switch self {
        case .classic: 40
        case .minimal: 12
        case .sport: 64
        case .analog: 48
        case .segmentedLED: 48
        case .digitalHUD: 0
        case .twinRing: 0
        }
    }

    var majorTickInterval: Int {
        switch self {
        case .classic: 10
        case .minimal: 6
        case .sport: 8
        case .analog: 8
        case .segmentedLED: 8
        case .digitalHUD: 1
        case .twinRing: 1
        }
    }

    var labelCount: Int {
        switch self {
        case .classic, .sport, .analog: 5
        case .minimal, .segmentedLED, .twinRing: 3
        case .digitalHUD: 0
        }
    }

    var showsTicks: Bool {
        switch self {
        case .classic, .sport, .analog: true
        case .minimal, .segmentedLED, .digitalHUD, .twinRing: false
        }
    }
}

final class AppAppearance: ObservableObject {
    static let shared = AppAppearance()

    @Published var theme: AppearanceTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.themeStorageKey) }
    }

    @Published var dialStyle: SpeedometerDialStyle {
        didSet { UserDefaults.standard.set(dialStyle.rawValue, forKey: Self.dialStorageKey) }
    }

    @Published var customBackgroundColor: Color {
        didSet { persistCustomColors() }
    }

    @Published var customAccentColor: Color {
        didSet { persistCustomColors() }
    }

    @Published var customPositiveColor: Color {
        didSet { persistCustomColors() }
    }

    private static let themeStorageKey = "speedometer.appearance.theme"
    private static let dialStorageKey = "speedometer.appearance.dialStyle"
    private static let customColorsStorageKey = "speedometer.appearance.customColors"

    private init() {
        theme = AppearanceTheme(rawValue: UserDefaults.standard.string(forKey: Self.themeStorageKey) ?? "") ?? .midnight
        dialStyle = SpeedometerDialStyle(rawValue: UserDefaults.standard.string(forKey: Self.dialStorageKey) ?? "") ?? .classic

        let savedPalette = UserDefaults.standard.data(forKey: Self.customColorsStorageKey)
            .flatMap { try? JSONDecoder().decode(StoredCustomPalette.self, from: $0) }
            ?? .defaults
        customBackgroundColor = savedPalette.background.color
        customAccentColor = savedPalette.accent.color
        customPositiveColor = savedPalette.positive.color
    }

    func resetCustomColors() {
        customBackgroundColor = AppearanceTheme.midnight.background
        customAccentColor = AppearanceTheme.midnight.accent
        customPositiveColor = AppearanceTheme.midnight.mint
    }

    private func persistCustomColors() {
        let palette = StoredCustomPalette(
            background: StoredThemeColor(color: customBackgroundColor),
            accent: StoredThemeColor(color: customAccentColor),
            positive: StoredThemeColor(color: customPositiveColor)
        )
        guard let data = try? JSONEncoder().encode(palette) else { return }
        UserDefaults.standard.set(data, forKey: Self.customColorsStorageKey)
    }
}

private struct StoredCustomPalette: Codable {
    let background: StoredThemeColor
    let accent: StoredThemeColor
    let positive: StoredThemeColor

    static let defaults = StoredCustomPalette(
        background: StoredThemeColor(color: AppearanceTheme.midnight.background),
        accent: StoredThemeColor(color: AppearanceTheme.midnight.accent),
        positive: StoredThemeColor(color: AppearanceTheme.midnight.mint)
    )
}

private struct StoredThemeColor: Codable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    init(color: Color) {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var opacity: CGFloat = 0
        if uiColor.getRed(&red, green: &green, blue: &blue, alpha: &opacity) {
            self.red = Double(red)
            self.green = Double(green)
            self.blue = Double(blue)
            self.opacity = Double(opacity)
        } else {
            self.red = 0
            self.green = 0
            self.blue = 0
            self.opacity = 1
        }
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
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

private func secondaryTextColor(on background: Color) -> Color {
    let luminance = relativeLuminance(of: background)
    let targetLuminance = luminance < 0.179
        ? min(1, 3 * (luminance + 0.05) - 0.05)
        : max(0, (luminance + 0.05) / 3 - 0.05)
    let srgb = targetLuminance <= 0.0031308
        ? targetLuminance * 12.92
        : 1.055 * pow(targetLuminance, 1 / 2.4) - 0.055
    return Color(white: srgb)
}
