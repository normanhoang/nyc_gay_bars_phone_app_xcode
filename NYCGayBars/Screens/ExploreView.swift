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

    private var coords: (lat: Double, lng: Double)? {
        location.coordinate.map { ($0.latitude, $0.longitude) }
    }

    private var distances: [String: Double]? {
        guard let c = coords else { return nil }
        var m: [String: Double] = [:]
        for b in AppData.bars { m[b.id] = Geo.distanceMiles(c.lat, c.lng, b) }
        return m
    }

    private var neighborhoodOptions: [String] {
        if let c = coords { return Geo.neighborhoodsByProximity(c.lat, c.lng) }
        return AppData.neighborhoods
    }

    private var filteredBars: [Bar] {
        let q = zip.query.trimmingCharacters(in: .whitespaces).lowercased()
        let d = distances
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
        neighborhood == "All" ? AppData.bars : AppData.bars.filter { $0.neighborhood == neighborhood }
    }

    private var visitedCount: Int {
        let ids = visits.visitedIds
        return neighborhoodBars.filter { ids.contains($0.id) }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            FilterChips(options: ["All"] + neighborhoodOptions, selected: Binding(
                get: { neighborhood }, set: { selectNeighborhood($0) }))
                .padding(.leading, 16)
                .padding(.bottom, 4)
            statsRow
            content
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
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.white)
                Spacer()
                Button(action: openInstagram) {
                    ZStack {
                        InstagramGlyph(size: 67, color: Color.white.opacity(0.315))
                        Image("AppLogo").resizable().scaledToFit().frame(width: 96, height: 96)
                    }
                }
                .buttonStyle(PressableScale())
                .accessibilityLabel("Open NYC Gay Bars on Instagram")
            }
            .padding(.bottom, 6)

            SearchBox(text: zip.query, onChangeText: { zip.change($0) }, onFocus: { mode = 1 })
                .padding(.bottom, 12)

            if let note = zip.zipNote {
                ZipNote(text: note).padding(.bottom, 8)
            }

            SegmentedToggle(options: ["Map", "List"], selection: $mode)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var statsRow: some View {
        HStack {
            HStack(spacing: 0) {
                Text("\(visitedCount) / \(neighborhoodBars.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.primary)
                Text(" visited · ").font(.system(size: 12)).foregroundStyle(Palette.gray500)
                Text(visitMessage(visitedCount, neighborhoodBars.count, neighborhood == "All"))
                    .font(.system(size: 12)).foregroundStyle(Palette.gray400)
            }
            if mode == 1 && distances != nil {
                Spacer()
                HStack(spacing: 0) {
                    Button { nearest = false } label: {
                        Text("A–Z").font(.system(size: 12, weight: nearest ? .semibold : .bold))
                            .foregroundStyle(nearest ? Palette.gray500 : Palette.primary)
                    }
                    Text(" · ").font(.system(size: 12)).foregroundStyle(Palette.gray600)
                    Button { nearest = true } label: {
                        Text("Nearest").font(.system(size: 12, weight: nearest ? .bold : .semibold))
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
    private var content: some View {
        if mode == 1 {
            if filteredBars.isEmpty {
                VStack(spacing: 8) {
                    Text("🔍").font(.system(size: 36))
                    Text("No bars match your search.")
                        .font(.system(size: 16)).foregroundStyle(Palette.gray400)
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
            }
        } else {
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

/// Faint Instagram glyph (rounded square + lens + flash dot) drawn behind the
/// header logo so it reads as an Instagram link.
private struct InstagramGlyph: View {
    var size: CGFloat
    var color: Color = Color.white.opacity(0.45)
    var body: some View {
        let lw = size * 0.07
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(color, lineWidth: lw)
            Circle()
                .stroke(color, lineWidth: lw)
                .frame(width: size * 0.52, height: size * 0.52)
            Circle()
                .fill(color)
                .frame(width: size * 0.10, height: size * 0.10)
                .offset(x: size * 0.27, y: -size * 0.27)
        }
        .frame(width: size, height: size)
    }
}
