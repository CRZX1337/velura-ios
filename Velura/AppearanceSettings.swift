import SwiftUI

// App-wide palettes and dial options. The observable settings object persists choices
// so every screen can react to the same appearance state.
enum AppearanceTheme: String, CaseIterable, Identifiable {
    case midnight
    case ocean
    case graphite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .midnight: "Midnight"
        case .ocean: "Ocean"
        case .graphite: "Graphite"
        }
    }

    var background: Color {
        switch self {
        case .midnight: Color(red: 0.025, green: 0.043, blue: 0.067)
        case .ocean: Color(red: 0.018, green: 0.070, blue: 0.078)
        case .graphite: Color(red: 0.055, green: 0.058, blue: 0.067)
        }
    }

    var secondary: Color {
        switch self {
        case .midnight: Color(red: 0.63, green: 0.70, blue: 0.77)
        case .ocean: Color(red: 0.66, green: 0.77, blue: 0.75)
        case .graphite: Color(red: 0.72, green: 0.73, blue: 0.76)
        }
    }

    var accent: Color {
        switch self {
        case .midnight: Color(red: 0.27, green: 0.79, blue: 0.98)
        case .ocean: Color(red: 0.24, green: 0.86, blue: 0.75)
        case .graphite: Color(red: 1.0, green: 0.69, blue: 0.28)
        }
    }

    var mint: Color {
        switch self {
        case .midnight: Color(red: 0.34, green: 0.91, blue: 0.73)
        case .ocean: Color(red: 0.48, green: 0.92, blue: 0.70)
        case .graphite: Color(red: 0.52, green: 0.88, blue: 0.65)
        }
    }

    var accentForeground: Color {
        switch self {
        case .midnight: .white
        case .ocean: Color(red: 0.015, green: 0.14, blue: 0.13)
        case .graphite: Color(red: 0.15, green: 0.10, blue: 0.025)
        }
    }

    var warning: Color { Color(red: 1.0, green: 0.34, blue: 0.31) }
}

enum SpeedometerDialStyle: String, CaseIterable, Identifiable {
    case classic
    case minimal
    case sport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .minimal: "Minimal"
        case .sport: "Sport"
        }
    }

    var trackWidth: CGFloat {
        switch self {
        case .classic: 10
        case .minimal: 7
        case .sport: 13
        }
    }

    var tickCount: Int {
        switch self {
        case .classic: 40
        case .minimal: 12
        case .sport: 64
        }
    }

    var majorTickInterval: Int {
        switch self {
        case .classic: 10
        case .minimal: 6
        case .sport: 8
        }
    }

    var labelCount: Int { self == .minimal ? 3 : 5 }
    var showsTicks: Bool { self != .minimal }
}

final class AppAppearance: ObservableObject {
    static let shared = AppAppearance()

    @Published var theme: AppearanceTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Self.themeStorageKey) }
    }

    @Published var dialStyle: SpeedometerDialStyle {
        didSet { UserDefaults.standard.set(dialStyle.rawValue, forKey: Self.dialStorageKey) }
    }

    private static let themeStorageKey = "speedometer.appearance.theme"
    private static let dialStorageKey = "speedometer.appearance.dialStyle"

    private init() {
        theme = AppearanceTheme(rawValue: UserDefaults.standard.string(forKey: Self.themeStorageKey) ?? "") ?? .midnight
        dialStyle = SpeedometerDialStyle(rawValue: UserDefaults.standard.string(forKey: Self.dialStorageKey) ?? "") ?? .classic
    }
}
