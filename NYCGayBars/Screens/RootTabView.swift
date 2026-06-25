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

    @State private var page: Int? = 0

    private let tabs: [(icon: String, label: String)] = [
        ("mug.fill", "Explore"),
        ("chart.bar.fill", "Stats"),
        ("clock.fill", "History"),
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

    private var tabBar: some View {
        GeometryReader { geo in
            let inner = geo.size.width
            let seg = inner / CGFloat(tabs.count)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                    .frame(width: seg)
                    .offset(x: seg * CGFloat(current))
                    .animation(Anim.chip, value: current)

                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.offset) { i, tab in
                        Button {
                            withAnimation(Anim.chip) { page = i }
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: tab.icon).font(.system(size: 20))
                                Text(tab.label).font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(current == i ? Palette.primary : Palette.gray400)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(6)
            .glassSurface(radius: 999, bordered: true)
        }
        .frame(width: 280, height: 64)
    }
}
