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

    private var visitedIds: Set<String> { visits.visitedIds }

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
                    Text("📊").font(.system(size: 36))
                    Text("Log your first drink to start earning stats and badges.")
                        .font(.system(size: 16)).foregroundStyle(Palette.gray400)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
            } else {
                content.transition(.opacity)
            }
        }
        .sheet(isPresented: $showAllBadges) { allBadgesSheet }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Stats").font(.system(size: 30, weight: .heavy)).foregroundStyle(.white)
                    .padding(.bottom, 16)

                Text("TOTALS").font(.system(size: 12, weight: .regular)).tracking(0.5)
                    .foregroundStyle(Palette.gray300).padding(.bottom, 8)
                HStack(spacing: 12) {
                    totalCell(Stats.totalDrinks(visits.visits), "drinks")
                    totalCell(Stats.totalDrinkDays(visits.visits), "drink-days")
                    totalCell(Stats.distinctBarsVisited(visits.visits), "bars")
                }
                .padding(.bottom, 12)

                if let fav = Stats.favoriteBar(visits.visits) {
                    statCard("FAVORITE BAR", fav.name, fav.neighborhood)
                }
                if let top = Stats.topDrinkType(visits.visits) {
                    statCard("TOP DRINK", "\(drinkEmoji(top.type)) \(top.type)", "\(top.count) logged all-time")
                }
                if let big = Stats.biggestNight(visits.visits) {
                    statCard("BIGGEST NIGHT", "\(big.total) \(big.total == 1 ? "drink" : "drinks")", DayKey.format(big.day))
                }
                let streak = Stats.longestDayStreak(visits.visits)
                if streak > 0 {
                    statCard("LONGEST STREAK", "\(streak) \(streak == 1 ? "day" : "days")", "Most consecutive days with drinks logged")
                }

                Text("Neighborhoods").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .padding(.top, 12).padding(.bottom, 8)
                neighborhoods

                HStack {
                    Text("Recent badges").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    Spacer()
                    Button { showAllBadges = true } label: {
                        HStack(spacing: 2) {
                            Text("All badges (\(earnedBadges.count)/\(badges.badges.count))")
                                .font(.system(size: 14, weight: .semibold))
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Palette.primary)
                    }
                    .buttonStyle(PressableScale())
                }
                .padding(.top, 20).padding(.bottom, 8)

                if recentBadges.isEmpty {
                    Text("No badges yet — log a drink to start earning.")
                        .font(.system(size: 14)).foregroundStyle(Palette.gray300)
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.05)))
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
            if p != 1 { scrollPos.scrollTo(edge: .top) }
        }
    }

    private func totalCell(_ value: Int, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text("\(value)").font(.system(size: 24, weight: .heavy)).foregroundStyle(Palette.primary)
            Text(label).font(.system(size: 12)).foregroundStyle(Palette.gray400)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8).padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.primary.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.primary.opacity(0.3), lineWidth: 1))
    }

    private func statCard(_ label: String, _ value: String, _ detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 12)).tracking(0.5).foregroundStyle(Palette.gray300)
            Text(value).font(.system(size: 20, weight: .heavy)).foregroundStyle(.white).padding(.top, 4)
            if let detail {
                Text(detail).font(.system(size: 12)).foregroundStyle(Palette.gray400).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.05)))
        .padding(.bottom, 12)
    }

    private var neighborhoods: some View {
        VStack(spacing: 0) {
            ForEach(Array(Stats.boroughProgress(visitedIds).enumerated()), id: \.element.id) { i, b in
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
                                .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.gray400)
                                .rotationEffect(.degrees(expanded ? 0 : -90))
                            Spacer()
                            Text("\(b.visited) / \(b.total)")
                                .font(.system(size: 12, weight: complete ? .bold : .semibold))
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
                                        .font(.system(size: 14)).foregroundStyle(.white)
                                    Spacer()
                                    Text("\(p.visited) / \(p.total)")
                                        .font(.system(size: 12, weight: done ? .bold : .semibold))
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
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private var allBadgesSheet: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                HStack {
                    Text("Badges · \(earnedBadges.count)/\(badges.badges.count) earned")
                        .font(.system(size: 18, weight: .heavy)).foregroundStyle(.white)
                    Spacer()
                    Button { showAllBadges = false } label: {
                        Image(systemName: "xmark").font(.system(size: 20)).foregroundStyle(.white)
                            .frame(width: 36, height: 36).glassSurface(radius: 18)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 12)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(milestonesLast(earnedBadges)) { BadgeTile(badge: $0, showDate: true) }
                        ForEach(milestonesLast(unearnedBadges)) { BadgeTile(badge: $0) }
                    }
                    .padding(16)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}
