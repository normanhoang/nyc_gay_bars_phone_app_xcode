import SwiftUI

/// Coordinates whether the tab pager responds to horizontal swipes. Explore's
/// map mode disables it (the map needs horizontal panning). Mirrors RN
/// components/TabSwipeContext.tsx. Also broadcasts the current page so each
/// page can reset its vertical scroll once it goes offscreen.
final class TabSwipe: ObservableObject {
    @Published var enabled = true
    @Published var page = 0
}

/// Root shell: three swipeable pages with a floating glass pill tab bar, plus
/// the global badge-unlock toast. Mirrors RN app/(tabs)/_layout.tsx.
struct RootTabView: View {
    @EnvironmentObject var visits: VisitsStore
    @EnvironmentObject var badges: BadgesStore
    @StateObject private var tabSwipe = TabSwipe()
    @Namespace private var tabNS

    @State private var page: Int? = 0
    @State private var pillPage: Int = 0

    private let tabs: [(icon: String, label: String)] = [
        ("wineglass.fill", "Explore"),
        ("chart.bar.fill", "Stats"),
        ("calendar", "History"),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ExploreView().containerRelativeFrame(.horizontal).id(0)
                    StatsView().containerRelativeFrame(.horizontal).id(1)
                    HistoryView().containerRelativeFrame(.horizontal).id(2)
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
                tabSwipe.page = p
                guard pillPage != p else { return }
                withAnimation(Anim.tab) { pillPage = p }
            }

            tabBar
                .padding(.bottom, 4)
        }
        .environmentObject(tabSwipe)
        .overlay(alignment: .top) { BadgeToast() }
        .onAppear { reconcile() }
        .onChange(of: visits.visits) { _, _ in reconcile() }
        .onChange(of: visits.visitedBars) { _, _ in reconcile() }
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
                    // Snappy (not bouncy) so the move feels instant on tap yet
                    // still rides an animation transaction — without one the
                    // matched-geometry pill is removed+reinserted and flashes.
                    withAnimation(.snappy(duration: 0.18)) { pillPage = i }
                    page = i
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon).font(.system(size: 15, weight: .semibold))
                        Text(tab.label).font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(active ? .white : Palette.gray400)
                    .frame(width: 92)
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
