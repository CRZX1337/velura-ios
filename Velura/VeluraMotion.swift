import SwiftUI

enum VeluraMotion {
    static let selection = Animation.spring(response: 0.38, dampingFraction: 0.84)
    static let content = Animation.spring(response: 0.44, dampingFraction: 0.9)
    static let stateChange = Animation.easeInOut(duration: 0.24)
    static let tabChange = Animation.easeInOut(duration: 0.28)
    static let gauge = Animation.smooth(duration: 0.45)

    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    static func transition(_ transition: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .identity : transition
    }
}
