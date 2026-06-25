import SwiftUI

/// One-shot pride-colored confetti burst that plays on mount. Drop inside an
/// absolute container; non-interactive. Port of RN components/Confetti.tsx.
struct Confetti: View {
    private struct Piece {
        let color: Color
        let w: CGFloat
        let h: CGFloat
        let startX: CGFloat      // fraction of width
        let drift: CGFloat       // horizontal travel (points)
        let launch: CGFloat      // upward initial velocity (points/sec, negative)
        let spin: Double         // total rotation (degrees)
        let duration: Double
        let delay: Double
    }

    private static let prideColors: [Color] = [
        Color(hex: "#e40303"), Color(hex: "#ff8c00"), Color(hex: "#ffed00"),
        Color(hex: "#008026"), Color(hex: "#004dff"), Color(hex: "#750787"),
        Color(hex: "#e0218a"), Color(hex: "#5bcefa"), Color(hex: "#f5a9b8"),
        Color.white,
    ]

    private let pieces: [Piece]
    private let start = Date()
    private let gravity: CGFloat = 900

    init(count: Int = 48, width: CGFloat = 380) {
        pieces = (0..<count).map { _ in
            let streamer = Bool.random()
            return Piece(
                color: Self.prideColors.randomElement()!,
                w: streamer ? .random(in: 4...7) : .random(in: 8...13),
                h: streamer ? .random(in: 16...28) : .random(in: 8...13),
                startX: .random(in: 0.25...0.75),
                drift: .random(in: -width / 1.6...width / 1.6),
                launch: .random(in: -190 ... -70),
                spin: .random(in: -760...760),
                duration: .random(in: 1.3...2.1),
                delay: .random(in: 0...0.14))
        }
    }

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { gc, size in
                let t = ctx.date.timeIntervalSince(start)
                for p in pieces {
                    let lt = t - p.delay
                    if lt < 0 || lt > p.duration { continue }
                    let progress = lt / p.duration
                    let x = size.width * p.startX + p.drift * CGFloat(progress)
                    // Upward launch then quadratic fall (origin near top).
                    let y = 40 + p.launch * CGFloat(lt) + 0.5 * gravity * CGFloat(lt * lt)
                    let opacity = progress < 0.82 ? 1.0 : max(0, 1 - (progress - 0.82) / 0.18)
                    let angle = Angle.degrees(p.spin * progress)

                    var rect = Path(CGRect(x: -p.w / 2, y: -p.h / 2, width: p.w, height: p.h))
                    rect = rect.applying(CGAffineTransform(rotationAngle: CGFloat(angle.radians))
                        .concatenating(CGAffineTransform(translationX: x, y: y)))
                    gc.fill(rect, with: .color(p.color.opacity(opacity)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
