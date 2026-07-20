import SwiftUI

/// Stats tab: totals, stat cards, neighborhood progress, recent badges, and an
/// all-badges sheet. Port of RN app/(tabs)/stats.tsx.
struct StatsView: View {
    @EnvironmentObject private var visits: VisitsStore
    @EnvironmentObject private var badges: BadgesStore
    @EnvironmentObject private var tabSwipe: TabSwipe
    @State private var showAllBadges = false
    @State private var expandedBoroughs: Set<String> = []
    @State private var scrollPos = ScrollPosition()
    // Cached so mutations made on other pages don't recompute the full stats
    // aggregation while this page is offscreen; refreshed on becoming active.
    @State private var snap: Snapshot?
    @State private var snapStale = false

    private var visitedIds: Set<String> { visits.visitedIds }

    /// All visit-derived stats gathered once per body pass instead of being
    /// recomputed inline per card.
    private struct Snapshot {
        let totalDrinks: Int
        let totalDrinkDays: Int
        let distinctBars: Int
        let favoriteBar: Bar?
        let topDrinkType: (type: String, count: Int)?
        let biggestNight: (day: String, total: Int)?
        let streak: Int
        let boroughs: [BoroughProgress]
    }

    private func makeSnapshot() -> Snapshot {
        let v = visits.visits
        return Snapshot(
            totalDrinks: Stats.totalDrinks(v),
            totalDrinkDays: Stats.totalDrinkDays(v),
            distinctBars: Stats.distinctBarsVisited(v),
            favoriteBar: Stats.favoriteBar(v),
            topDrinkType: Stats.topDrinkType(v),
            biggestNight: Stats.biggestNight(v),
            streak: Stats.longestDayStreak(v),
            boroughs: Stats.boroughProgress(visitedIds))
    }

    private var earnedBadges: [Badge] {
        badges.badges.filter { $0.earned }
            .sorted { ($0.earnedAt ?? "") > ($1.earnedAt ?? "") }
    }
    private var unearnedBadges: [Badge] { badges.badges.filter { !$0.earned } }
    private var recentBadges: [Badge] { Array(earnedBadges.prefix(4)) }

    private func milestonesLast(_ list: [Badge]) -> [Badge] {
        list.filter { !Stats.milestoneBadgeIds.contains($0.id) }
            + list.filter { Stats.milestoneBadgeIds.contains($0.id) }
    }

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        Group {
            if !visits.hydrated {
                Color.clear
            } else if visits.visits.isEmpty && visitedIds.isEmpty {
                VStack(spacing: 12) {
                    Text("📊").font(.scaled(36))
                    Text("Log your first drink to start earning stats and badges.")
                        .font(.scaled(16)).foregroundStyle(Palette.gray400)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            } else {
                content(snap ?? makeSnapshot()).transition(.opacity)
            }
        }
        .sheet(isPresented: $showAllBadges) { allBadgesSheet }
        .onAppear { snap = makeSnapshot() }
        .onChange(of: SnapshotKey(visits: visits.visits, visitedIds: visits.visitedIds)) { _, _ in
            if tabSwipe.page == .stats {
                snap = makeSnapshot()
            } else {
                snapStale = true
            }
        }
        .onChange(of: tabSwipe.page) { _, p in
            if p == .stats && snapStale {
                snap = makeSnapshot()
                snapStale = false
            }
        }
    }

    /// Change key for the data the snapshot is derived from.
    private struct SnapshotKey: Equatable {
        let visits: [Visit]
        let visitedIds: Set<String>
    }

    private func content(_ snap: Snapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Stats").font(.scaled(30, weight: .heavy)).foregroundStyle(.white)
                    .padding(.bottom, 16)

                Text("TOTALS").font(.scaled(12, weight: .regular)).tracking(0.5)
                    .foregroundStyle(Palette.gray300).padding(.bottom, 8)
                HStack(spacing: 12) {
                    totalCell(snap.totalDrinks, "drinks")
                    totalCell(snap.totalDrinkDays, "drink-days")
                    totalCell(snap.distinctBars, "bars")
                }
                .padding(.bottom, 12)

                if let fav = snap.favoriteBar {
                    statCard("FAVORITE BAR", fav.name, fav.neighborhood)
                }
                if let top = snap.topDrinkType {
                    statCard("TOP DRINK", "\(drinkEmoji(top.type)) \(top.type)", "\(top.count) logged all-time")
                }
                if let big = snap.biggestNight {
                    statCard("BIGGEST NIGHT", "\(big.total) \(big.total == 1 ? "drink" : "drinks")", DayKey.format(big.day))
                }
                if snap.streak > 0 {
                    statCard("LONGEST STREAK", "\(snap.streak) \(snap.streak == 1 ? "day" : "days")", "Most consecutive days with drinks logged")
                }

                Text("Neighborhoods").font(.scaled(16, weight: .bold)).foregroundStyle(.white)
                    .padding(.top, 12).padding(.bottom, 8)
                neighborhoods(snap.boroughs)

                HStack {
                    Text("Recent badges").font(.scaled(16, weight: .bold)).foregroundStyle(.white)
                    Spacer()
                    Button { showAllBadges = true } label: {
                        HStack(spacing: 2) {
                            Text("All badges (\(earnedBadges.count)/\(badges.badges.count))")
                                .font(.scaled(14, weight: .semibold))
                            Image(systemName: "chevron.right").font(.scaled(12, weight: .semibold))
                        }
                        .foregroundStyle(Palette.primary)
                    }
                    .buttonStyle(PressableScale())
                }
                .padding(.top, 20).padding(.bottom, 8)

                if recentBadges.isEmpty {
                    Text("No badges yet — log a drink to start earning.")
                        .font(.scaled(14)).foregroundStyle(Palette.gray300)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .contentPanel()
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(recentBadges) { BadgeTile(badge: $0) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 104)
        }
        .scrollPosition($scrollPos)
        // Reset scroll once this page goes offscreen so the next visit always
        // starts at the top.
        .onChange(of: tabSwipe.page) { _, p in
            if p != .stats { scrollPos.scrollTo(edge: .top) }
        }
    }

    private func totalCell(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 4) {
            CountUp(value: value, font: .scaled(24, weight: .heavy), color: Palette.primary)
            Text(label).font(.scaled(12)).foregroundStyle(Palette.gray400)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.primary.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.primary.opacity(0.3), lineWidth: 1))
    }

    private func statCard(_ label: String, _ value: String, _ detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.scaled(12)).tracking(0.5).foregroundStyle(Palette.gray300)
            Text(value).font(.scaled(20, weight: .heavy)).foregroundStyle(.white).padding(.top, 4)
            if let detail {
                Text(detail).font(.scaled(12)).foregroundStyle(Palette.gray400).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .contentPanel()
        .padding(.bottom, 12)
    }

    private func neighborhoods(_ boroughs: [BoroughProgress]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(boroughs.enumerated()), id: \.element.id) { i, b in
                let complete = b.visited == b.total
                let expanded = expandedBoroughs.contains(b.borough)
                Button {
                    withAnimation(Anim.chip) {
                        if expanded { expandedBoroughs.remove(b.borough) }
                        else { expandedBoroughs.insert(b.borough) }
                    }
                } label: {
                    VStack(spacing: 6) {
                        HStack {
                            Text(b.borough + (complete ? " 👑" : ""))
                                .font(.scaled(15, weight: .bold)).foregroundStyle(.white)
                            Image(systemName: "chevron.down")
                                .font(.scaled(11, weight: .semibold))
                                .foregroundStyle(Palette.gray400)
                                .rotationEffect(.degrees(expanded ? 0 : -90))
                            Spacer()
                            Text("\(b.visited) / \(b.total)")
                                .font(.scaled(12, weight: complete ? .bold : .semibold))
                                .foregroundStyle(complete ? Palette.primary : Palette.gray400)
                        }
                        ProgressBar(progress: Double(b.visited) / Double(b.total), delay: Double(i) * 0.06)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    VStack(spacing: 0) {
                        ForEach(b.neighborhoods) { p in
                            let done = p.visited == p.total
                            VStack(spacing: 6) {
                                HStack {
                                    Text(p.neighborhood + (done ? " 👑" : ""))
                                        .font(.scaled(14)).foregroundStyle(.white)
                                    Spacer()
                                    Text("\(p.visited) / \(p.total)")
                                        .font(.scaled(12, weight: done ? .bold : .semibold))
                                        .foregroundStyle(done ? Palette.primary : Palette.gray400)
                                }
                                ProgressBar(progress: Double(p.visited) / Double(p.total))
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.leading, 16)
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .contentPanel()
    }

    private var allBadgesSheet: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                HStack {
                    Text("Badges · \(earnedBadges.count)/\(badges.badges.count) earned")
                        .font(.scaled(18, weight: .heavy)).foregroundStyle(.white)
                    Spacer()
                    Button { showAllBadges = false } label: {
                        Image(systemName: "xmark").font(.scaled(20)).foregroundStyle(.white)
                            .frame(width: 36, height: 36).glassSurface(radius: 18)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 12)

                ScrollView {
                    let progressById = Stats.badgeProgress(visits.visits, visits.visitedIds)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(milestonesLast(earnedBadges)) { BadgeTile(badge: $0, showDate: true) }
                        ForEach(milestonesLast(unearnedBadges)) {
                            BadgeTile(badge: $0, progress: progressById[$0.id])
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}
