import SwiftUI

/// Slim track with a magenta→violet gradient fill that springs to a 0–1
/// progress. `delay` staggers rows. Port of RN components/ProgressBar.tsx.
struct ProgressBar: View {
    var progress: Double
    var delay: Double = 0

    @State private var w: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(LinearGradient(
                        colors: [Palette.primary, Palette.violet],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * max(0, min(1, w)))
            }
        }
        .frame(height: 8)
        .onAppear {
            withAnimation(Anim.progress.delay(delay)) { w = progress }
        }
        .onChange(of: progress) { _, nv in
            withAnimation(Anim.progress) { w = nv }
        }
    }
}
