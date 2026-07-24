import SwiftUI

/// Stats tab: totals, stat cards, neighborhood progress, recent badges, and an
/// all-badges sheet. Port of RN app/(tabs)/stats.tsx.
struct StatsView: View {
    @EnvironmentObject private var visits: VisitsStore
    @EnvironmentObject private var badges: BadgesStore
    @EnvironmentObject private var tabSwipe: TabSwipe
    @State private var showAllBadges = false
    @State private var showRecap = false
    @State private var badgeFilter: BadgeFilter = .all
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

    /// The two unearned countable badges closest to completion (redesign 1b).
    private func upNext() -> [(badge: Badge, current: Int, target: Int)] {
        let progress = Stats.badgeProgress(visits.visits, visits.visitedIds)
        let rows: [(badge: Badge, current: Int, target: Int)] = unearnedBadges.compactMap { b in
            guard let p = progress[b.id] else { return nil }
            return (badge: b, current: p.current, target: p.target)
        }
        return rows
            .sorted {
                let fa = Double($0.current) / Double($0.target)
                let fb = Double($1.current) / Double($1.target)
                if fa != fb { return fa > fb }
                return ($0.target - $0.current) < ($1.target - $1.current)
            }
            .prefix(2)
            .map { $0 }
    }

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
        .fullScreenCover(isPresented: $showRecap) {
            RecapView(year: Stats.recapYear(), onClose: { showRecap = false })
        }
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
                Text("Stats").font(.scaled(22, weight: .heavy)).foregroundStyle(.white)
                    .padding(.bottom, 16)

                HStack(spacing: 12) {
                    totalCell(snap.totalDrinks, "drinks")
                    totalCell(snap.totalDrinkDays, "drink-days")
                    totalCell(snap.distinctBars, "bars")
                }
                .padding(.bottom, 12)

                LazyVGrid(columns: columns, spacing: 12) {
                    if let fav = snap.favoriteBar {
                        statCard("FAVORITE BAR", fav.name, fav.neighborhood)
                    }
                    if let top = snap.topDrinkType {
                        statCard("TOP DRINK", "\(drinkEmoji(top.type)) \(top.type)", "\(top.count) all-time")
                    }
                    if let big = snap.biggestNight {
                        statCard("BIGGEST NIGHT", "\(big.total) \(big.total == 1 ? "drink" : "drinks")", DayKey.format(big.day))
                    }
                    if snap.streak > 0 {
                        statCard("LONGEST STREAK", "\(snap.streak) \(snap.streak == 1 ? "day" : "days")", "In a row with drinks")
                    }
                }

                let recapYear = Stats.recapYear()
                if !Stats.visitsIn(year: recapYear, visits.visits).isEmpty {
                    Button { showRecap = true } label: {
                        HStack {
                            Text("🪩")
                            Text("Your \(String(recapYear)) Recap")
                                .font(.scaled(15, weight: .bold)).foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.scaled(12, weight: .semibold)).foregroundStyle(Palette.gray400)
                        }
                        .padding(16)
                        .contentPanel(radius: 16)
                    }
                    .buttonStyle(PressableScale())
                    .padding(.top, 12)
                }

                let next = upNext()
                if !next.isEmpty {
                    HStack {
                        Text("Up next").font(.scaled(16, weight: .bold)).foregroundStyle(.white)
                        Spacer()
                        Button { showAllBadges = true } label: {
                            HStack(spacing: 2) {
                                Text("All badges · \(earnedBadges.count)/\(badges.badges.count)")
                                    .font(.scaled(13, weight: .semibold))
                                Image(systemName: "chevron.right").font(.scaled(11, weight: .semibold))
                            }
                            .foregroundStyle(Palette.gray400)
                        }
                        .buttonStyle(PressableScale())
                    }
                    .padding(.top, 20).padding(.bottom, 8)
                    upNextPanel(next)
                }

                Text("Neighborhoods").font(.scaled(16, weight: .bold)).foregroundStyle(.white)
                    .padding(.top, 20).padding(.bottom, 8)
                neighborhoods(snap.boroughs)
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
            Text(label).font(.scaled(11)).tracking(0.5).foregroundStyle(Palette.gray400)
            Text(value).font(.scaled(17, weight: .bold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.8).padding(.top, 4)
            if let detail {
                Text(detail).font(.scaled(11)).foregroundStyle(Palette.gray600)
                    .lineLimit(1).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .contentPanel(radius: 16)
    }

    private func upNextPanel(_ next: [(badge: Badge, current: Int, target: Int)]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(next.enumerated()), id: \.element.badge.id) { i, item in
                BadgeProgressRow(
                    badge: item.badge, current: item.current, target: item.target,
                    delay: Double(i) * 0.06,
                    caption: Stats.progressCaption(item.badge.id, current: item.current, target: item.target))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .contentPanel()
    }

    /// One line per borough: name · progress bar · count (redesign 1b).
    private func neighborhoods(_ boroughs: [BoroughProgress]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(boroughs.enumerated()), id: \.element.id) { i, b in
                let complete = b.visited == b.total
                HStack(spacing: 12) {
                    Text(b.borough + (complete ? " 👑" : ""))
                        .font(.scaled(14, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 96, alignment: .leading)
                    ProgressBar(progress: Double(b.visited) / Double(b.total),
                                delay: Double(i) * 0.06, height: 6)
                    Text("\(b.visited)/\(b.total)")
                        .font(.scaled(12, weight: complete ? .bold : .semibold))
                        .foregroundStyle(complete ? Palette.primary : Palette.gray400)
                }
                .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .contentPanel()
    }

    private enum BadgeFilter: CaseIterable { case all, earned, inProgress }

    private var allBadgesSheet: some View {
        let progressById = Stats.badgeProgress(visits.visits, visits.visitedIds)
        // Unearned countable badges with any progress, closest to done first.
        let inProgress: [(badge: Badge, current: Int, target: Int)] = unearnedBadges
            .compactMap { b in
                guard let p = progressById[b.id], p.current > 0 else { return nil }
                return (badge: b, current: p.current, target: p.target)
            }
            .sorted { Double($0.current) / Double($0.target) > Double($1.current) / Double($1.target) }
        let inProgressIds = Set(inProgress.map(\.badge.id))
        let locked = unearnedBadges.filter { !inProgressIds.contains($0.id) }

        return ZStack {
            AppBackground()
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Badges").font(.scaled(18, weight: .heavy)).foregroundStyle(.white)
                    Text("\(earnedBadges.count) of \(badges.badges.count)")
                        .font(.scaled(13)).foregroundStyle(Palette.gray400)
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

                HStack(spacing: 8) {
                    filterChip("All", .all)
                    filterChip("Earned · \(earnedBadges.count)", .earned)
                    filterChip("In progress · \(inProgress.count)", .inProgress)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if badgeFilter != .earned && !inProgress.isEmpty {
                            sectionLabel("ALMOST THERE")
                            VStack(spacing: 0) {
                                let rows = badgeFilter == .all ? Array(inProgress.prefix(5)) : inProgress
                                ForEach(Array(rows.enumerated()), id: \.element.badge.id) { i, item in
                                    BadgeProgressRow(
                                        badge: item.badge, current: item.current,
                                        target: item.target, delay: Double(i) * 0.06)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 6)
                            .contentPanel()
                            .padding(.bottom, 20)
                        }

                        if badgeFilter != .inProgress && !earnedBadges.isEmpty {
                            sectionLabel("EARNED")
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(milestonesLast(earnedBadges)) {
                                    BadgeTile(badge: $0, showDate: true, showDescription: false)
                                }
                            }
                            .padding(.bottom, 20)
                        }

                        if badgeFilter == .all && !locked.isEmpty {
                            sectionLabel("MORE BADGES")
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(milestonesLast(locked)) {
                                    BadgeTile(badge: $0, progress: progressById[$0.id])
                                }
                            }
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.scaled(12)).tracking(0.8)
            .foregroundStyle(Palette.gray400)
            .padding(.bottom, 8)
    }

    private func filterChip(_ label: String, _ value: BadgeFilter) -> some View {
        let active = badgeFilter == value
        return Button {
            withAnimation(Anim.chip) { badgeFilter = value }
            Haptics.selection()
        } label: {
            Text(label)
                .font(.scaled(13, weight: .semibold))
                .foregroundStyle(active ? .white : Palette.gray300)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(active ? Palette.primary : Color.white.opacity(0.08)))
                .overlay {
                    if !active { Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
                }
        }
        .buttonStyle(PressableScale())
    }
}
