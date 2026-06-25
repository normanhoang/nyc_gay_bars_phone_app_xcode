import SwiftUI

/// Coordinates whether the tab pager responds to horizontal swipes. Explore's
/// map mode disables it (the map needs horizontal panning). Mirrors RN
/// components/TabSwipeContext.tsx.
final class TabSwipe: ObservableObject {
    @Published var enabled = true
}

/// Root shell: three swipeable pages with a floating glass pill tab bar, plus
/// the global badge-unlock toast. Mirrors RN app/(tabs)/_layout.tsx.
struct RootTabView: View {
    @EnvironmentObject var visits: VisitsStore
    @EnvironmentObject var badges: BadgesStore
    @StateObject private var tabSwipe = TabSwipe()
    @Namespace private var tabNS

    @State private var page: Int? = 0

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

    // Every tab uses a fixed-size content box, so the active lozenge — matched
    // to that box via matchedGeometryEffect — is identical at every position and
    // never crowds the glass edge. The bouncy spring lives on `current`, so it
    // overshoots whether the page changes by tap or by swipe.
    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { i, tab in
                let active = current == i
                Button {
                    withAnimation(Anim.tab) { page = i }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.icon).font(.system(size: 18, weight: .semibold))
                        Text(tab.label).font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(active ? .white : Palette.gray400)
                    .frame(width: 70, height: 40)
                    .scaleEffect(active ? 1.06 : 1)
                    .background {
                        if active {
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [Palette.primary, Palette.primaryDark],
                                    startPoint: .top, endPoint: .bottom))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.30), lineWidth: 0.5))
                                .shadow(color: Palette.primary.opacity(0.5), radius: 6, y: 2)
                                .matchedGeometryEffect(id: "tabPill", in: tabNS)
                        }
                    }
                    .padding(8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .glassSurface(radius: 28, bordered: true)
        .animation(Anim.tab, value: current)
    }
}
