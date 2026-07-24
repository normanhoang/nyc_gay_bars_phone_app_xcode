import SwiftUI
import UIKit

/// Explore tab: List/Map of bars with search (+ ZIP interception), neighborhood
/// filter chips, and A–Z/Nearest sort. Port of RN app/(tabs)/index.tsx.
struct ExploreView: View {
    @EnvironmentObject private var visits: VisitsStore
    @EnvironmentObject private var tabSwipe: TabSwipe
    @EnvironmentObject private var social: SocialStore
    @StateObject private var zip = ZipQuery()
    @StateObject private var location = LocationManager()

    @State private var mode = 0          // 0 = Map, 1 = List
    @State private var nearest = true    // sort: Nearest vs A–Z
    @State private var neighborhood = "All"
    @State private var selectedBar: Bar?
    @State private var showQuickLog = false
    @State private var frameNonce = 0
    @State private var scrollPos = ScrollPosition()

    private var coords: (lat: Double, lng: Double)? {
        location.coordinate.map { ($0.latitude, $0.longitude) }
    }

    private var distances: [String: Double]? {
        coords.map { Geo.derived($0.lat, $0.lng).distances }
    }

    private var neighborhoodOptions: [String] {
        if let c = coords { return Geo.derived(c.lat, c.lng).neighborhoodsByProximity }
        return AppData.neighborhoods
    }

    private func filteredBars(_ d: [String: Double]?) -> [Bar] {
        let q = zip.query.trimmingCharacters(in: .whitespaces).lowercased()
        return AppData.bars.filter { b in
            if neighborhood != "All" && b.neighborhood != neighborhood { return false }
            if !q.isEmpty {
                let hay = "\(b.name) \(b.neighborhood) \(b.address) \(b.tags?.joined(separator: " ") ?? "")".lowercased()
                if !hay.contains(q) { return false }
            }
            return true
        }.sorted { a, b in
            if nearest, let d {
                return (d[a.id] ?? .infinity) < (d[b.id] ?? .infinity)
            }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }

    private var neighborhoodBars: [Bar] {
        neighborhood == "All" ? AppData.bars : (AppData.barsByNeighborhood[neighborhood] ?? [])
    }

    /// Closest bar by live distance, nil without a location fix (redesign 1c).
    private func nearestBar(_ d: [String: Double]?) -> Bar? {
        guard let d else { return nil }
        return AppData.bars.min { (d[$0.id] ?? .infinity) < (d[$1.id] ?? .infinity) }
    }

    /// Friends' active check-ins as avatar pins, one per bar (redesign 3a).
    private var friendPins: [FriendPin] {
        Dictionary(grouping: social.tonight, by: \.barId).compactMap { barId, checkIns in
            guard let bar = AppData.barsById[barId] else { return nil }
            let names = Array(Set(checkIns.map(\.authorName))).sorted()
            return FriendPin(
                id: barId,
                label: names.count == 1 ? "\(names[0]) is here" : "\(names.count) friends here",
                initial: String(names[0].prefix(1)).uppercased(),
                barId: barId, latitude: bar.latitude, longitude: bar.longitude)
        }
    }

    var body: some View {
        // Derived per body pass, not per access — distances is ~80 haversines
        // and filteredBars a filter+sort; both were computed properties read
        // several times per render.
        let d = distances
        let bars = filteredBars(d)
        VStack(spacing: 0) {
            header(hasDistances: d != nil)
            FilterChips(options: ["All"] + neighborhoodOptions, selected: Binding(
                get: { neighborhood }, set: { selectNeighborhood($0) }))
                .padding(.leading, 16)
                .padding(.bottom, 4)
            statsRow()
            content(d, bars)
        }
        // Quick-log FAB (redesign 1c) — nudged up when the coverage callout
        // occupies the bottom of the map.
        .overlay(alignment: .bottomTrailing) {
            Button {
                Haptics.light()
                showQuickLog = true
            } label: {
                Image(systemName: "plus")
                    .font(.scaled(24, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(Palette.primary))
                    .shadow(color: Palette.primary.opacity(0.45), radius: 10, y: 2)
            }
            .buttonStyle(PressableScale())
            .accessibilityLabel("Quick log")
            .padding(.trailing, 16)
            .padding(.bottom, mode == 0 && neighborhood != "All" ? 176 : 92)
        }
        .sheet(isPresented: $showQuickLog) {
            QuickLogSheet(initialBar: nearestBar(d), distances: d)
                .environmentObject(visits)
        }
        .dismissKeyboardOnBackgroundTap()
        .onAppear { location.start(); tabSwipe.enabled = (mode == 1) }
        .onChange(of: mode) { _, m in tabSwipe.enabled = (m == 1) }
        // Tapping the Explore tab resets the neighborhood filter to All.
        .onChange(of: tabSwipe.exploreResetTick) { _, _ in
            if neighborhood != "All" { selectNeighborhood("All") }
        }
        // Tonight "Map" chip: frame the friend's bar in map mode (redesign 4a).
        .onChange(of: tabSwipe.mapTarget) { _, target in
            guard let id = target, let bar = AppData.barsById[id] else { return }
            tabSwipe.mapTarget = nil
            mode = 0
            selectNeighborhood(bar.neighborhood)
        }
        .sheet(item: $selectedBar) { bar in
            BarDetailSheet(bar: bar, day: nil)
                .environmentObject(visits)
        }
        .onAppear { zip.onZip = { selectNeighborhood($0) } }
    }

    private func header(hasDistances: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("NYC Gay Bars")
                    .font(.scaled(22, weight: .heavy))
                    .foregroundStyle(.white)
                Spacer()
                Button(action: openInstagram) {
                    InstagramGlyph(size: 36, corner: 12)
                }
                .buttonStyle(PressableScale())
                .accessibilityLabel("Open NYC Gay Bars on Instagram")
            }
            .padding(.bottom, 10)

            SearchBox(text: zip.query, placeholder: "Search bars, ZIP…",
                      onChangeText: { zip.change($0) }, onFocus: { mode = 1 }) {
                if hasDistances {
                    sortChip
                }
            }
            .padding(.bottom, 12)

            if let note = zip.zipNote {
                ZipNote(text: note).padding(.bottom, 8)
            }

            SegmentedToggle(options: ["Map", "List"], selection: $mode)

            if location.denied {
                Button(action: openLocationSettings) {
                    HStack(spacing: 8) {
                        Image(systemName: "location.slash")
                            .font(.scaled(14)).foregroundStyle(Palette.gray300)
                        Text("Enable location for distances & Nearest sort")
                            .font(.scaled(13, weight: .medium)).foregroundStyle(Palette.gray300)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.scaled(12, weight: .semibold)).foregroundStyle(Palette.gray400)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .glassSurface(radius: 16, bordered: true)
                }
                .buttonStyle(PressableScale())
                .padding(.top, 12)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func openLocationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    /// Sort toggle chip that lives inside the search bar (redesign 1a).
    private var sortChip: some View {
        Button {
            nearest.toggle()
            Haptics.selection()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.scaled(11, weight: .semibold))
                Text(nearest ? "Nearest" : "A–Z")
                    .font(.scaled(12, weight: .semibold))
            }
            .foregroundStyle(Palette.gray200)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(nearest ? "nearest" : "name")")
    }

    private func statsRow() -> some View {
        let bars = neighborhoodBars
        let ids = visits.visitedIds
        let visitedCount = bars.filter { ids.contains($0.id) }.count
        return HStack(spacing: 0) {
            Text("\(visitedCount) of \(bars.count) visited")
                .font(.scaled(12, weight: .semibold))
                .foregroundStyle(Palette.gray300)
            Text(" · " + visitMessage(visitedCount, bars.count, neighborhood == "All"))
                .font(.scaled(12)).foregroundStyle(Palette.gray400)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func content(_ distances: [String: Double]?, _ filteredBars: [Bar]) -> some View {
        if mode == 1 {
            if filteredBars.isEmpty {
                VStack(spacing: 8) {
                    Text("🔍").font(.scaled(36))
                    Text("No bars match your search or filters.")
                        .font(.scaled(16)).foregroundStyle(Palette.gray400)
                    Button { selectNeighborhood("All") } label: {
                        Text("Clear search & filters")
                            .font(.scaled(14, weight: .semibold))
                            .foregroundStyle(Palette.primary)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Capsule().fill(Palette.primary.opacity(0.15)))
                            .overlay(Capsule().strokeBorder(Palette.primary.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(PressableScale())
                    .padding(.top, 4)
                }
                .padding(.top, 64)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredBars) { bar in
                            BarListItem(
                                bar: bar,
                                distance: distances?[bar.id],
                                visited: visits.visitedIds.contains(bar.id),
                                drinkCount: visits.getVisitFor(bar.id)?.drinkTotal ?? 0,
                                onTap: { selectedBar = bar })
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 104)
                }
                .scrollDismissesKeyboard(.immediately)
                .scrollPosition($scrollPos)
                // Reset scroll once this page goes offscreen so the next visit
                // always starts at the top.
                .onChange(of: tabSwipe.page) { _, p in
                    if p != .explore { scrollPos.scrollTo(edge: .top) }
                }
            }
        } else {
            ZStack(alignment: .top) {
                BarMapView(
                    bars: filteredBars,
                    showOutlines: neighborhood == "All" && zip.query.trimmingCharacters(in: .whitespaces).isEmpty,
                    visitedIds: visits.visitedIds,
                    frameNonce: frameNonce,
                    friendPins: friendPins,
                    onSelectBar: { selectedBar = AppData.bar(id: $0) },
                    onSelectNeighborhood: { selectNeighborhood($0) },
                    onZoomOut: {
                        if neighborhood == "All" { return false }
                        neighborhood = "All"
                        return true
                    })

                if filteredBars.isEmpty {
                    HStack(spacing: 12) {
                        Text("No bars match your search.")
                            .font(.scaled(14, weight: .medium)).foregroundStyle(.white)
                        Button { selectNeighborhood("All") } label: {
                            Text("Clear search")
                                .font(.scaled(13, weight: .semibold))
                                .foregroundStyle(Palette.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .glassSurface(radius: 16, bordered: true)
                    .padding(.top, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                if neighborhood != "All" {
                    coverageCallout
                }
            }
        }
    }

    /// Floating neighborhood coverage callout above the tab bar (redesign 3a).
    private var coverageCallout: some View {
        let bars = neighborhoodBars
        let visitedCount = bars.filter { visits.visitedIds.contains($0.id) }.count
        let remaining = bars.count - visitedCount
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(neighborhood)
                    .font(.scaled(14, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Text("\(visitedCount) / \(bars.count) visited")
                    .font(.scaled(12, weight: .semibold)).foregroundStyle(Palette.gray300)
            }
            ProgressBar(progress: bars.isEmpty ? 0 : Double(visitedCount) / Double(bars.count), height: 6)
            Text(remaining > 0
                 ? "\(remaining) to go for Neighborhood Hero 🏘️"
                 : "Neighborhood Hero earned 🏘️")
                .font(.scaled(11)).foregroundStyle(Palette.gray400)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.ink.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 92)
    }

    private func selectNeighborhood(_ value: String) {
        if value == neighborhood { frameNonce += 1 }
        neighborhood = value
        zip.query = ""
    }

    private func openInstagram() {
        let app = URL(string: "instagram://user?username=thenycgaybars")!
        let web = URL(string: "https://www.instagram.com/thenycgaybars")!
        UIApplication.shared.open(app, options: [:]) { ok in
            if !ok { UIApplication.shared.open(web) }
        }
    }

    private func visitMessage(_ visited: Int, _ total: Int, _ isAll: Bool) -> String {
        if total == 0 { return "" }
        if visited == 0 { return "Never been — time to explore!" }
        if visited == total {
            return isAll ? "You've conquered the scene! 👑" : "You've conquered the neighborhood! 👑"
        }
        let pct = Double(visited) / Double(total)
        if pct <= 0.25 { return "Just getting started..." }
        if pct <= 0.5 { return "Making the rounds!" }
        if pct <= 0.75 { return "A regular on the scene!" }
        return "Almost a legend!"
    }
}

/// Instagram glyph (rounded square + lens + flash dot) drawn behind the header
/// logo so it reads as an Instagram link. The outline is rendered in native
/// Liquid Glass — a `.glassEffect` squircle masked to the stroke shapes.
private struct InstagramGlyph: View {
    var size: CGFloat
    var corner: CGFloat? = nil
    private var cornerRadius: CGFloat { corner ?? size * 0.28 }
    var body: some View {
        ZStack {
            // Full Liquid Glass squircle tile — maximum glass surface.
            Color.clear
                .frame(width: size, height: size)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            // Faint Instagram cues (frame edge + lens + flash dot) on the glass.
            outline(lineWidth: max(size * 0.04, 1.2), color: .white.opacity(0.35))
        }
        .frame(width: size, height: size)
        // The base is Color.clear (non-hit-testable), so without this the
        // enclosing button only registers taps on the thin outline strokes.
        .contentShape(Rectangle())
    }

    private func outline(lineWidth: CGFloat, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius * 0.6, style: .continuous)
                .strokeBorder(color, lineWidth: lineWidth)
                .padding(size * 0.18)
            Circle()
                .stroke(color, lineWidth: lineWidth)
                .frame(width: size * 0.30, height: size * 0.30)
            Circle()
                .fill(color)
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(x: size * 0.185, y: -size * 0.185)
        }
        .frame(width: size, height: size)
    }
}
