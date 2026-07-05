import SwiftUI

/// Animatable number that eases from its current value to a new one. Remount
/// via `.id(...)` to replay from zero. Port of RN components/CountUp.tsx.
struct CountUp: View {
    let value: Int
    var font: Font = .scaled(24, weight: .heavy)
    var color: Color = Palette.primary
    var duration: Double = 0.42

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var n: Double = 0

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .modifier(CountText(number: n, font: font, color: color))
            .onAppear {
                if reduceMotion { n = Double(value); return }
                n = 0
                withAnimation(.easeOut(duration: duration)) { n = Double(value) }
            }
            .onChange(of: value) { _, nv in
                if reduceMotion { n = Double(nv); return }
                withAnimation(.easeOut(duration: duration)) { n = Double(nv) }
            }
    }
}

private struct CountText: AnimatableModifier {
    var number: Double
    var font: Font
    var color: Color

    var animatableData: Double {
        get { number }
        set { number = newValue }
    }

    func body(content: Content) -> some View {
        Text(verbatim: String(Int(number.rounded())))
            .font(font)
            .foregroundStyle(color)
            .fixedSize()
    }
}
