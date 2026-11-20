import SwiftUI

enum VeluraMotion {
    static let selection = Animation.spring(response: 0.34, dampingFraction: 0.84)
    static let morph = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let content = Animation.spring(response: 0.44, dampingFraction: 0.9)
    static let stateChange = Animation.smooth(duration: 0.26)
    static let tabChange = Animation.smooth(duration: 0.28)
    static let gauge = Animation.smooth(duration: 0.36)
    static let ambient = Animation.smooth(duration: 0.65)
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.82)

    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    static func transition(_ transition: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : transition
    }
}
