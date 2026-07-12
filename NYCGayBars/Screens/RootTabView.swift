import SwiftUI

/// Coordinates whether the tab pager responds to horizontal swipes. Explore's
/// map mode disables it (the map needs horizontal panning). Mirrors RN
/// components/TabSwipeContext.tsx. Also broadcasts the current page so each
/// page can reset its vertical scroll once it goes offscreen.
final class TabSwipe: ObservableObject {
    @Published var enabled = true
    @Published var page = 0
    /// Bumped each time the Explore tab button is tapped (even when already on
    /// Explore) so ExploreView can reset its filter to "All".
    @Published var exploreResetTick = 0
}

/// Root shell: three swipeable pages with a floating glass pill tab bar, plus
/// the global badge-unlock toast. Mirrors RN app/(tabs)/_layout.tsx.
struct RootTabView: View {
    @EnvironmentObject var visits: VisitsStore
    @EnvironmentObject var badges: BadgesStore
    @EnvironmentObject var social: SocialStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var tabSwipe = TabSwipe()
    @Namespace private var tabNS

    @State private var page: Int? = 0
    @State private var pillPage: Int = 0
    /// Bar opened from a tapped friend check-in notification.
    @State private var deepLinkBar: Bar?

    private let tabs: [(icon: String, label: String)] = [
        ("wineglass.fill", "Explore"),
        ("chart.bar.fill", "Stats"),
        ("calendar", "History"),
        ("person.2.fill", "Friends"),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ExploreView().containerRelativeFrame(.horizontal).id(0)
                    StatsView().containerRelativeFrame(.horizontal).id(1)
                    HistoryView().containerRelativeFrame(.horizontal).id(2)
                    FriendsView().containerRelativeFrame(.horizontal).id(3)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $page)
            // Only Explore (page 0) in map mode blocks the pager; Stats/History
            // stay swipeable regardless.
            .scrollDisabled(current == 0 && !tabSwipe.enabled)
            .scrollIndicators(.hidden)
            .ignoresSafeArea(.keyboard)
            .onChange(of: page) { _, newPage in
                guard let p = newPage else { return }
                if tabSwipe.page != p {
                    Haptics.selection()
                    dismissKeyboard()
                }
                tabSwipe.page = p
                guard pillPage != p else { return }
                withAnimation(Anim.tab) { pillPage = p }
            }

            tabBar
                .padding(.bottom, 4)
                // Fixed-width tabs; unbounded text sizes would clip the labels.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        }
        // Scaled fonts support Dynamic Type up to a cap the layouts can hold.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .environmentObject(tabSwipe)
        // Hidden while a sheet with its own BadgeToast is up, so an unlock
        // during logging shows once (in the sheet) rather than here too.
        .overlay(alignment: .top) {
            if badges.toastModalDepth == 0 { BadgeToast() }
        }
        .onAppear { reconcile() }
        // Single change key so a mutation touching both visits and visitedBars
        // (e.g. setVisited(false)) triggers one reconcile, not two.
        .onChange(of: ReconcileKey(visits: visits.visits, visitedBars: visits.visitedBars)) { _, _ in
            reconcile()
        }
        .onAppear { consumeDeepLink() }
        .onChange(of: social.deepLinkBarId) { _, _ in consumeDeepLink() }
        // Returning to the app reconciles any acceptance whose silent push was
        // dropped or arrived before CloudKit was consistent, so a new friend
        // shows up without a manual pull-to-refresh.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await social.reconcilePendingAcceptances() } }
        }
        // Add-friend link/QR: land the user on the Friends tab so they see
        // the auto-sent request (or onboarding, if not set up yet).
        .onChange(of: social.pendingAddCode) { _, code in
            guard code != nil, pillPage != 3 else { return }
            withAnimation(.snappy(duration: 0.18)) { pillPage = 3 }
            page = 3
        }
        .sheet(item: $deepLinkBar) { bar in
            BarDetailSheet(bar: bar, day: nil)
        }
    }

    /// Open the bar detail for a tapped "friend is at …" notification.
    private func consumeDeepLink() {
        guard let id = social.deepLinkBarId else { return }
        social.deepLinkBarId = nil
        if let bar = AppData.barsById[id] { deepLinkBar = bar }
    }

    private struct ReconcileKey: Equatable {
        let visits: [Visit]
        let visitedBars: [String]
    }

    private func reconcile() {
        badges.reconcile(visits: visits.visits, visitedIds: visits.visitedIds)
    }

    private var current: Int { page ?? 0 }

    // Full-width segmented bar. pillPage drives the active highlight independently
    // from page so tap is instant and swipe gets the bouncy spring (via onChange).
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { i, tab in
                let active = pillPage == i
                Button {
                    // Tapping Explore always resets its filter to All, even when
                    // already on Explore (page won't change, so signal via tick).
                    if i == 0 { tabSwipe.exploreResetTick += 1 }
                    // Snappy (not bouncy) so the move feels instant on tap yet
                    // still rides an animation transaction — without one the
                    // matched-geometry pill is removed+reinserted and flashes.
                    withAnimation(.snappy(duration: 0.18)) { pillPage = i }
                    page = i
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon).font(.scaled(15, weight: .semibold))
                        Text(tab.label).font(.scaled(10, weight: .semibold))
                    }
                    .foregroundStyle(active ? .white : Palette.gray400)
                    // 80pt (was 92 with three tabs) so four tabs clear the
                    // screen margins on the smallest supported width.
                    .frame(width: 80)
                    .padding(.vertical, 8)
                    .background {
                        if active {
                            Capsule(style: .continuous)
                                .fill(Palette.primary)
                                .shadow(color: Palette.primary.opacity(0.45), radius: 7)
                                .matchedGeometryEffect(id: "tabPill", in: tabNS)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .glassSurface(radius: 30, bordered: true)
    }
}
