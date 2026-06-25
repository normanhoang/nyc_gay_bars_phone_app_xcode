import SwiftUI

/// Spring curves mapped 1:1 from the RN reanimated physical springs so motion
/// matches the original app.
enum Anim {
    static let chip = Animation.interpolatingSpring(mass: 0.6, stiffness: 220, damping: 18)
    static let press = Animation.interpolatingSpring(mass: 0.5, stiffness: 400, damping: 15)
    static let progress = Animation.interpolatingSpring(mass: 0.7, stiffness: 140, damping: 20)
    static let toast = Animation.interpolatingSpring(mass: 0.7, stiffness: 200, damping: 16)
    /// Bouncy overshoot for the bottom tab-bar selection lozenge.
    static let tab = Animation.bouncy(duration: 0.45, extraBounce: 0.22)
}

/// Button style that springs to 0.97 while held — the Apple "squish".
/// Port of RN components/PressableScale.tsx.
struct PressableScale: ButtonStyle {
    var scaleTo: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleTo : 1)
            .animation(Anim.press, value: configuration.isPressed)
    }
}

extension View {
    /// Convenience: wrap a tap target so it presses with the squish scale.
    func pressableScale(_ scaleTo: CGFloat = 0.97, action: @escaping () -> Void) -> some View {
        Button(action: action) { self }.buttonStyle(PressableScale(scaleTo: scaleTo))
    }
}
