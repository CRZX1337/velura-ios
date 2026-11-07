import SwiftUI

struct AdaptiveFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let size: CGFloat
    var weight: Font.Weight = .regular
    var design: Font.Design = .default
    var usesMonospacedDigits = false

    func monospacedDigit() -> Self {
        var copy = self
        copy.usesMonospacedDigits = true
        return copy
    }

    func body(content: Content) -> some View {
        let font = Font.system(size: size * dynamicTypeSize.veluraScaleFactor, weight: weight, design: design)
        content.font(usesMonospacedDigits ? font.monospacedDigit() : font)
    }
}

extension DynamicTypeSize {
    var veluraScaleFactor: CGFloat {
        switch self {
        case .xSmall: 0.9
        case .small: 0.95
        case .medium: 0.98
        case .large: 1
        case .xLarge: 1.08
        case .xxLarge: 1.17
        case .xxxLarge: 1.27
        case .accessibility1: 1.42
        case .accessibility2: 1.58
        case .accessibility3: 1.75
        case .accessibility4: 1.91
        case .accessibility5: 2.08
        @unknown default: 1
        }
    }
}
