import SwiftUI
import UIKit

extension Font {
    /// Dynamic Type–aware system font: identical to the old fixed
    /// `.system(size:weight:)` at the default text size, but scales with the
    /// user's text-size setting (bodies re-run on the environment change, so
    /// the metric is re-read).
    static func scaled(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: UIFontMetrics.default.scaledValue(for: size), weight: weight)
    }
}
