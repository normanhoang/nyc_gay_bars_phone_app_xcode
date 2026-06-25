import SwiftUI

/// Liquid Glass surface for chrome/controls only (search bars, toggles, buttons,
/// toasts, tab bar). Uses native iOS 26 `.glassEffect`. Static content panels
/// should use `.contentPanel()` instead. Mirrors RN components/Glass.tsx rules:
/// corner radius is a parameter (the glass layer shapes itself), a faint white
/// fill adds contrast, and an optional hairline border crisps the edge.
struct GlassSurface: ViewModifier {
    var radius: CGFloat
    var bordered: Bool = false
    var borderColor: Color = Color.white.opacity(0.16)

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .glassEffect(.regular, in: .rect(cornerRadius: radius))
            }
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 0.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Static translucent content panel (stat cards, calendar, visit cards). No
/// glass — native glass draws an un-disableable rim that reads as a border.
struct ContentPanel: ViewModifier {
    var radius: CGFloat = 24
    var fill: Color = Color.white.opacity(0.05)

    func body(content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
    }
}

extension View {
    func glassSurface(radius: CGFloat, bordered: Bool = false,
                      borderColor: Color = Color.white.opacity(0.16)) -> some View {
        modifier(GlassSurface(radius: radius, bordered: bordered, borderColor: borderColor))
    }

    func contentPanel(radius: CGFloat = 24, fill: Color = Color.white.opacity(0.05)) -> some View {
        modifier(ContentPanel(radius: radius, fill: fill))
    }
}
