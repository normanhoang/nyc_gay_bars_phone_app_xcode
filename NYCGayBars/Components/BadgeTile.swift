import SwiftUI

/// Badge medallion. Earned tiles get a magenta→violet gradient; milestone
/// badges get a faint gold outline; unearned content is dimmed. Port of RN
/// components/BadgeTile.tsx.
struct BadgeTile: View {
    let badge: Badge
    var showDate: Bool = false

    private var isMilestone: Bool { Stats.milestoneBadgeIds.contains(badge.id) }

    private var earnedDateText: String? {
        guard showDate, badge.earned, let iso = badge.earnedAt else { return nil }
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: DayKey.parseISO(iso))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(badge.emoji)
                .font(.system(size: 40))
            Text(badge.title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
            Text(badge.description)
                .font(.system(size: 12))
                .foregroundStyle(Palette.gray400)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            if let date = earnedDateText {
                Text(date)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.primary)
                    .padding(.top, 8)
            }
        }
        .opacity(badge.earned ? 1 : 0.4)
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
