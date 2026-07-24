import SwiftUI

/// Compact progress row for an unearned badge: emoji, title (+ gold milestone
/// tag), running count and a slim gradient bar. Used by Stats' "Up next" panel
/// and the all-badges sheet (redesigns 1b/6b).
struct BadgeProgressRow: View {
    let badge: Badge
    let current: Int
    let target: Int
    var delay: Double = 0
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(badge.emoji).font(.scaled(24))
                Text(badge.title)
                    .font(.scaled(14, weight: .bold)).foregroundStyle(.white)
                if Stats.milestoneBadgeIds.contains(badge.id) {
                    Text("milestone")
                        .font(.scaled(11, weight: .semibold)).foregroundStyle(Palette.gold)
                }
                Spacer()
                Text("\(min(current, target)) / \(target)")
                    .font(.scaled(11, weight: .semibold)).foregroundStyle(Palette.gray400)
            }
            ProgressBar(progress: Double(current) / Double(max(target, 1)), delay: delay, height: 6)
            if let caption {
                Text(caption).font(.scaled(11)).foregroundStyle(Palette.gray600)
            }
        }
        .padding(.vertical, 10)
    }
}
