import UIKit

/// Thin haptics wrappers mirroring RN lib/haptics.ts.
enum Haptics {
    /// Light tap on drink +/- and similar small interactions.
    static func light() {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
    }

    /// Success notification fired when a badge is earned.
    static func success() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
    }

    /// Selection tick for tab and segment switches.
    static func selection() {
        let gen = UISelectionFeedbackGenerator()
        gen.selectionChanged()
    }

    /// Warning notification fired when confirming a destructive action.
    static func warning() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.warning)
    }
}
