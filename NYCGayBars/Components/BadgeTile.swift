import SwiftUI

/// Badge medallion. Earned tiles get a magenta→violet gradient; milestone
/// badges get a faint gold outline; unearned content is dimmed. Port of RN
/// components/BadgeTile.tsx.
struct BadgeTile: View {
    let badge: Badge
    var showDate: Bool = false
    /// Running count toward an unearned badge, e.g. (3, 5) → "3 / 5".
    var progress: (current: Int, target: Int)? = nil

    private var isMilestone: Bool { Stats.milestoneBadgeIds.contains(badge.id) }

    private var earnedDateText: String? {
        guard showDate, badge.earned, let iso = badge.earnedAt else { return nil }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: DayKey.parseISO(iso))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Text(badge.emoji)
                    .font(.scaled(40))
                Text(badge.title)
                    .font(.scaled(14, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                Text(badge.description)
                    .font(.scaled(12))
                    .foregroundStyle(Palette.gray400)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                if let date = earnedDateText {
                    Text(date)
                        .font(.scaled(10, weight: .semibold))
                        .foregroundStyle(Palette.primary)
                        .padding(.top, 8)
                }
            }
            .opacity(badge.earned ? 1 : 0.4)

            // Progress stays at full opacity so the running count is readable.
            if !badge.earned, let p = progress {
                VStack(spacing: 4) {
                    ProgressBar(progress: Double(p.current) / Double(max(p.target, 1)))
                    Text("\(min(p.current, p.target)) / \(p.target)")
                        .font(.scaled(10, weight: .semibold))
                        .foregroundStyle(Palette.gray400)
                }
                .padding(.top, 10)
                .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 160)
        .padding(12)
        .background {
            if badge.earned {
                LinearGradient(
                    colors: [Palette.primary.opacity(0.35), Palette.violetGlow.opacity(0.22)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                Color.white.opacity(0.04)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            if isMilestone {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Palette.gold.opacity(badge.earned ? 0.5 : 0.25), lineWidth: 1)
            }
        }
    }
}
