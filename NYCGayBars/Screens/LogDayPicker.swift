import SwiftUI

/// Backdated bar picker reached from History's "Add drinks for this day".
/// Picking a bar slides up the logger in-place (no nested navigation), so close
/// always lands back on History. Port of RN app/log/[day].tsx.
struct LogDayPicker: View {
    let day: String

    @EnvironmentObject private var visits: VisitsStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var zip = ZipQuery()
    @StateObject private var location = LocationManager()

    @State private var neighborhood = "All"
    @State private var nearest = true
    @State private var picked: Bar?

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
            if nearest, let d { return (d[a.id] ?? .infinity) < (d[b.id] ?? .infinity) }
            return a.name.localizedCompare(b.name) == .orderedAscending
        }
    }

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 0) {
                HStack {
                    Text("Pick a bar").font(.system(size: 18, weight: .heavy)).foregroundStyle(.white)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 20)).foregroundStyle(.white)
                            .frame(width: 36, height: 36).glassSurface(radius: 18)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 4)

                VStack(spacing: 0) {
                    Text("Logging drinks for \(DayKey.format(day)) — which bar were you at?")
                        .font(.system(size: 14)).foregroundStyle(Palette.gray400)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 12)
                    SearchBox(text: zip.query, onChangeText: { zip.change($0) })
                    if let note = zip.zipNote { ZipNote(text: note).padding(.top, 8) }
                }
                .padding(.horizontal, 16).padding(.bottom, 12)

                FilterChips(options: ["All"] + neighborhoodOptions, selected: Binding(
                    get: { neighborhood }, set: { selectNeighborhood($0) }))
                    .padding(.leading, 16).padding(.bottom, 8)

                if distances != nil {
                    HStack(spacing: 0) {
                        Spacer()
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
                    .padding(.horizontal, 16).padding(.bottom, 8)
                }

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredBars) { bar in
                            BarListItem(
                                bar: bar,
                                distance: distances?[bar.id],
                                visited: visits.visitedIds.contains(bar.id),
                                drinkCount: visits.getVisitFor(bar.id, day: day)?.drinkTotal ?? 0,
                                onTap: { withAnimation(.easeOut(duration: 0.32)) { picked = bar } })
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.immediately)
            }

            if let bar = picked {
                BarDetailSheet(bar: bar, day: day,
                               onClose: { withAnimation(.easeOut(duration: 0.32)) { picked = nil } })
                    .environmentObject(visits)
                    .transition(.move(edge: .bottom))
                    .zIndex(1)
            }
        }
        .onAppear { location.start(); zip.onZip = { selectNeighborhood($0) } }
    }

    private func selectNeighborhood(_ value: String) {
        neighborhood = value
        zip.query = ""
    }
}
