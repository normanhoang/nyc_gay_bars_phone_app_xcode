import SwiftUI

/// Full-screen gradient wash rendered behind every screen so the Liquid Glass
/// surfaces have colour to refract. Matches RN components/AppBackground.tsx.
struct AppBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Primary plum → ink diagonal.
                LinearGradient(
                    stops: [
                        .init(color: Palette.plum, location: 0),
                        .init(color: Palette.inkMid, location: 0.55),
                        .init(color: Palette.inkDeep, location: 1),
                    ],
                    startPoint: UnitPoint(x: 0.1, y: 0),
                    endPoint: UnitPoint(x: 0.9, y: 1))

                // Magenta glow, top-right.
                LinearGradient(
                    colors: [Palette.primary.opacity(0.18), Palette.primary.opacity(0)],
                    startPoint: UnitPoint(x: 1, y: 0),
                    endPoint: UnitPoint(x: 0.2, y: 0.6))
                    .frame(height: geo.size.height * 0.6)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .allowsHitTesting(false)

                // Violet rise, bottom.
                LinearGradient(
                    colors: [Palette.violetGlow.opacity(0), Palette.violetGlow.opacity(0.14)],
                    startPoint: UnitPoint(x: 0.3, y: 0),
                    endPoint: UnitPoint(x: 0.7, y: 1))
                    .frame(height: geo.size.height * 0.45)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
