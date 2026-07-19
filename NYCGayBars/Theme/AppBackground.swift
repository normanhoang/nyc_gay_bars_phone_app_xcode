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

                // Magenta glow, top-right. Radial so it fades smoothly to
                // transparent in every direction — no clipped frame edge.
                RadialGradient(
                    colors: [Palette.primary.opacity(0.18), Palette.primary.opacity(0)],
                    center: UnitPoint(x: 1, y: 0),
                    startRadius: 0,
                    endRadius: geo.size.height * 0.6)
                    .allowsHitTesting(false)

                // Violet rise, bottom.
                RadialGradient(
                    colors: [Palette.violetGlow.opacity(0.14), Palette.violetGlow.opacity(0)],
                    center: UnitPoint(x: 0.5, y: 1),
                    startRadius: 0,
                    endRadius: geo.size.height * 0.5)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
