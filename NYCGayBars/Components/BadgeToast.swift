import SwiftUI

/// Floating "BADGE UNLOCKED" banner at the top of the screen, driven by the
/// BadgesStore unlock queue. Plays confetti for milestone badges. Port of RN
/// components/BadgeToast.tsx. Mount once per screen layer (safe to duplicate).
struct BadgeToast: View {
    @EnvironmentObject var badges: BadgesStore

    var body: some View {
        VStack {
            if let badge = badges.unlocked.first {
                ToastBanner(badge: badge)
                    .id(badge.id)
                    .onTapGesture { badges.dismissUnlocked() }
                    .padding(.horizontal, 24)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(badges.unlocked.first != nil)
    }
}

private struct ToastBanner: View {
    let badge: Badge

    @State private var shown = false
    @State private var emojiScale: CGFloat = 0
    @State private var emojiRotate: Double = 0

    private var isMilestone: Bool { Stats.milestoneBadgeIds.contains(badge.id) }

    var body: some View {
        ZStack(alignment: .top) {
            if isMilestone {
                Confetti()
                    .frame(height: 820)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            HStack(spacing: 12) {
                Text(badge.emoji)
                    .font(.system(size: 24))
                    .scaleEffect(emojiScale)
                    .rotationEffect(.degrees(emojiRotate))
                VStack(alignment: .leading, spacing: 1) {
                    Text(isMilestone ? "MILESTONE UNLOCKED" : "BADGE UNLOCKED")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Palette.gray300)
                    Text(badge.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassSurface(radius: 24, bordered: true, borderColor: Palette.primary.opacity(0.5))
        }
        .offset(y: shown ? 0 : -120)
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(Anim.toast) { shown = true }
            withAnimation(.easeOut(duration: 0.22)) {
                emojiScale = 1.4
                emojiRotate = 8
            }
            withAnimation(Anim.toast.delay(0.22)) {
                emojiScale = 1
                emojiRotate = 0
            }
        }
    }
}
