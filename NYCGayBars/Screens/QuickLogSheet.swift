import SwiftUI

/// One-handed logging sheet opened from Explore's FAB (redesign 1c): nearest
/// bar pre-selected (or a picker when location is unavailable), the user's
/// most-used drinks up front, and a session context strip after each log.
struct QuickLogSheet: View {
    /// Nearest bar by location, nil when no fix.
    var initialBar: Bar?
    var distances: [String: Double]?

    @EnvironmentObject private var visits: VisitsStore
    @EnvironmentObject private var badges: BadgesStore
    @Environment(\.dismiss) private var dismiss

    @State private var bar: Bar?
    @State private var showPicker = false
    @State private var hasLogged = false

    private var today: String { DayKey.key() }
    private var visit: Visit? { bar.flatMap { visits.getVisitFor($0.id, day: today) } }

    private var featuredDrinks: [String] { Stats.topDrinkTypes(visits.visits) }

    var body: some View {
        ZStack(alignment: .top) {
            AppBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Quick log")
                        .font(.scaled(20, weight: .heavy)).foregroundStyle(.white)
                    Text(initialBar != nil ? "Based on your location" : "Pick where you are")
                        .font(.scaled(12)).foregroundStyle(Palette.gray400)
                        .padding(.top, 2)

                    barCard.padding(.top, 12)

                    if hasLogged, let context = sessionContext() {
                        Text(context)
                            .font(.scaled(13, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10).padding(.horizontal, 12)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Palette.primary.opacity(0.2)))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Palette.primary.opacity(0.35), lineWidth: 1))
                            .padding(.top, 12)
                            .transition(.opacity)
                    }

                    if let bar {
                        DrinkLogger(
                            visit: visit,
                            featured: featuredDrinks,
                            expandLabel: "All drinks",
                            onLog: { type in
                                visits.logDrink(bar.id, type, day: today)
                                withAnimation(.easeOut(duration: 0.2)) { hasLogged = true }
                            },
                            onRemove: { visits.removeDrink(bar.id, $0, day: today) })
                            .padding(.top, 16)
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }

            BadgeToast().padding(.top, 8)
        }
        .onAppear { if bar == nil { bar = initialBar } }
        .sheet(isPresented: $showPicker) {
            QuickLogBarPicker(distances: distances) { picked in
                bar = picked
                showPicker = false
            }
        }
        // Own a toast layer while visible so the root toast defers to this one.
        .onAppear { badges.pushToastModal() }
        .onDisappear { badges.popToastModal() }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var barCard: some View {
        HStack(spacing: 12) {
            if let bar {
                VStack(alignment: .leading, spacing: 2) {
                    Text(bar.name)
                        .font(.scaled(15, weight: .bold)).foregroundStyle(.white)
                    (Text(bar.neighborhood).foregroundStyle(Palette.primary)
                        + Text(distanceText(bar).map { " · \($0)" } ?? "").foregroundStyle(Palette.gray400))
                        .font(.scaled(12, weight: .medium))
                }
                Spacer()
                Button { showPicker = true } label: {
                    Text("Change")
                        .font(.scaled(14, weight: .semibold)).foregroundStyle(Palette.primary)
                }
                .buttonStyle(.plain)
            } else {
                Button { showPicker = true } label: {
                    HStack {
                        Text("Choose a bar")
                            .font(.scaled(15, weight: .semibold)).foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.scaled(13, weight: .semibold)).foregroundStyle(Palette.gray400)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .glassSurface(radius: 16, bordered: true)
    }

    private func distanceText(_ bar: Bar) -> String? {
        guard let d = distances?[bar.id] else { return nil }
        return d < 0.19 ? "\(Int((d * 5280).rounded())) ft away"
                        : String(format: "%.1f mi away", d)
    }

    /// "🍻 That's your 3rd drink tonight · 2nd bar" from today's visits.
    private func sessionContext() -> String? {
        let todays = visits.getVisitsForDay(today)
        let drinks = todays.reduce(0) { $0 + $1.drinkTotal }
        guard drinks > 0 else { return nil }
        let bars = Set(todays.map(\.barId)).count
        var text = "🍻 That's your \(ordinal(drinks)) drink tonight"
        if bars > 1 { text += " · \(ordinal(bars)) bar" }
        return text
    }

    private func ordinal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

/// Searchable, proximity-sorted bar picker for the quick log sheet.
private struct QuickLogBarPicker: View {
    var distances: [String: Double]?
    var onPick: (Bar) -> Void

    @EnvironmentObject private var visits: VisitsStore
    @State private var query = ""

    private var results: [Bar] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return AppData.bars.filter { b in
            q.isEmpty || "\(b.name) \(b.neighborhood)".lowercased().contains(q)
        }.sorted { a, b in
            if let d = distances {
                return (d[a.id] ?? .infinity) < (d[b.id] ?? .infinity)
            }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                SearchBox(text: query, placeholder: "Search bars…",
                          onChangeText: { query = $0 })
                    .padding(16)
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(results) { bar in
                            BarListItem(
                                bar: bar,
                                distance: distances?[bar.id],
                                visited: visits.visitedIds.contains(bar.id),
                                drinkCount: visits.getVisitFor(bar.id)?.drinkTotal ?? 0,
                                onTap: { onPick(bar) })
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.immediately)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
