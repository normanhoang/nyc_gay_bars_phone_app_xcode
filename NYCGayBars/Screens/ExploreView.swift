import SwiftUI
import UIKit

/// Explore tab: List/Map of bars with search (+ ZIP interception), neighborhood
/// filter chips, and A–Z/Nearest sort. Port of RN app/(tabs)/index.tsx.
struct ExploreView: View {
    @EnvironmentObject private var visits: VisitsStore
    @EnvironmentObject private var tabSwipe: TabSwipe
    @StateObject private var zip = ZipQuery()
    @StateObject private var location = LocationManager()

    @State private var mode = 0          // 0 = Map, 1 = List
    @State private var nearest = true    // sort: Nearest vs A–Z
    @State private var neighborhood = "All"
    @State private var selectedBar: Bar?
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

    var body: some View {
        // Derived per body pass, not per access — distances is ~80 haversines
        // and filteredBars a filter+sort; both were computed properties read
        // several times per render.
        let d = distances
        let bars = filteredBars(d)
        VStack(spacing: 0) {
            header
            FilterChips(options: ["All"] + neighborhoodOptions, selected: Binding(
                get: { neighborhood }, set: { selectNeighborhood($0) }))
                .padding(.leading, 16)
                .padding(.bottom, 4)
            statsRow(d)
            content(d, bars)
        }
        .dismissKeyboardOnBackgroundTap()
        .onAppear { location.start(); tabSwipe.enabled = (mode == 1) }
        .onChange(of: mode) { _, m in tabSwipe.enabled = (m == 1) }
        .sheet(item: $selectedBar) { bar in
            BarDetailSheet(bar: bar, day: nil)
                .environmentObject(visits)
        }
        .onAppear { zip.onZip = { selectNeighborhood($0) } }
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("NYC Gay Bars")
                    .font(.scaled(30, weight: .heavy))
                    .foregroundStyle(.white)
                Spacer()
                Button(action: openInstagram) {
                    ZStack {
                        InstagramGlyph(size: 66)
                        Image("AppLogo").resizable().scaledToFit().frame(width: 96, height: 96)
                    }
                }
                .buttonStyle(PressableScale())
                .offset(x: 12)
                .accessibilityLabel("Open NYC Gay Bars on Instagram")
            }
            .padding(.bottom, 6)

            SearchBox(text: zip.query, onChangeText: { zip.change($0) }, onFocus: { mode = 1 })
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

    private func statsRow(_ distances: [String: Double]?) -> some View {
        let bars = neighborhoodBars
        let ids = visits.visitedIds
        let visitedCount = bars.filter { ids.contains($0.id) }.count
        return HStack {
            HStack(spacing: 0) {
                Text("\(visitedCount) / \(bars.count)")
                    .font(.scaled(12, weight: .semibold))
                    .foregroundStyle(Palette.primary)
                Text(" visited · ").font(.scaled(12)).foregroundStyle(Palette.gray500)
                Text(visitMessage(visitedCount, bars.count, neighborhood == "All"))
                    .font(.scaled(12)).foregroundStyle(Palette.gray400)
            }
            if mode == 1 && distances != nil {
                Spacer()
                HStack(spacing: 0) {
                    Button { nearest = false } label: {
                        Text("A–Z").font(.scaled(12, weight: nearest ? .semibold : .bold))
                            .foregroundStyle(nearest ? Palette.gray500 : Palette.primary)
                    }
                    Text(" · ").font(.scaled(12)).foregroundStyle(Palette.gray600)
                    Button { nearest = true } label: {
                        Text("Nearest").font(.scaled(12, weight: nearest ? .bold : .semibold))
                            .foregroundStyle(nearest ? Palette.primary : Palette.gray500)
                    }
                }
                .buttonStyle(.plain)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: mode == 1 && distances != nil ? .leading : .center)
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
                    if p != 0 { scrollPos.scrollTo(edge: .top) }
                }
            }
        } else {
            ZStack(alignment: .top) {
                BarMapView(
                    bars: filteredBars,
                    showOutlines: neighborhood == "All" && zip.query.trimmingCharacters(in: .whitespaces).isEmpty,
                    visitedIds: visits.visitedIds,
                    frameNonce: frameNonce,
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
        }
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
    var body: some View {
        let corner = size * 0.28
        ZStack {
            // Full Liquid Glass squircle tile — maximum glass surface.
            Color.clear
                .frame(width: size, height: size)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            // Faint Instagram cues (frame edge + lens + flash dot) on the glass.
            outline(lineWidth: size * 0.04, color: .white.opacity(0.22))
        }
        .frame(width: size, height: size)
    }

    private func outline(lineWidth: CGFloat, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(color, lineWidth: lineWidth)
            Circle()
                .stroke(color, lineWidth: lineWidth)
                .frame(width: size * 0.52, height: size * 0.52)
            Circle()
                .fill(color)
                .frame(width: size * 0.10, height: size * 0.10)
                .offset(x: size * 0.27, y: -size * 0.27)
        }
        .frame(width: size, height: size)
    }
}
