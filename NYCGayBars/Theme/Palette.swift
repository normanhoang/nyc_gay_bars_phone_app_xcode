import SwiftUI

extension Color {
    init(hex: String, opacity: Double = 1) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >> 8) & 0xFF) / 255
        let b = Double(v & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

/// App color palette, matching the RN tailwind.config.js theme exactly.
enum Palette {
    static let primary = Color(hex: "#e0218a")
    static let primaryDark = Color(hex: "#b81873")
    static let ink = Color(hex: "#0b0b12")

    // Background gradient stops.
    static let plum = Color(hex: "#2a1033")
    static let inkMid = Color(hex: "#1a0f26")
    static let inkDeep = Color(hex: "#120f1d")

    // Accent gradient endpoints (badge tiles, progress bar).
    static let violet = Color(hex: "#a23bd6")
    static let violetGlow = Color(hex: "#6e3cbe")

    // Milestone gold (badge outlines).
    static let gold = Color(hex: "#e3b341")

    // Tailwind grays used across the UI.
    static let gray200 = Color(hex: "#e5e7eb")
    static let gray300 = Color(hex: "#d1d5db")
    static let gray400 = Color(hex: "#9ca3af")
    static let gray500 = Color(hex: "#6b7280")
    static let gray600 = Color(hex: "#4b5563")
    static let gray700 = Color(hex: "#374151")
    static let red = Color(hex: "#ef4444")
    static let green = Color(hex: "#22c55e")
}
