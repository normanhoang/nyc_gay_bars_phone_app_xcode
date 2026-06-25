import SwiftUI
import MapKit

/// Interactive Apple Map. In "outlines" mode (All + empty search) it draws
/// tappable neighborhood polygons; otherwise it drops bar pins. Zooming out far
/// enough to span 2+ neighborhoods switches the filter to All. Port of RN
/// components/BarMap.tsx.
struct BarMapView: View {
    let bars: [Bar]
    let showOutlines: Bool
    let visitedIds: Set<String>
    let frameNonce: Int
    var onSelectBar: (String) -> Void
    var onSelectNeighborhood: (String) -> Void
    /// Returns true if the zoom-out actually changed the filter (suppress reframe).
    var onZoomOut: () -> Bool

    @State private var camera: MapCameraPosition = .automatic
    @State private var framedSpan: Double = 0.22
    @State private var suppressNextFrame = false
    /// Set when we programmatically reframe; the next camera-change records the
    /// real rendered span (which MapKit may enlarge to fit a wide region) so the
    /// zoom-out check compares against what's actually on screen.
    @State private var awaitingFrame = false
    /// Bumped on every frame() request so coalesced async applies keep only the last.
    @State private var frameGen = 0

    var body: some View {
        MapReader { proxy in
            Map(position: $camera) {
                UserAnnotation()
                if showOutlines {
                    ForEach(AppData.neighborhoods, id: \.self) { name in
                        if let ring = AppData.neighborhoodPolygons[name] {
                            MapPolygon(coordinates: ring.map {
                                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                            })
                            .foregroundStyle(Palette.primary.opacity(0.18))
                            .stroke(Palette.primary, lineWidth: 2)
                        }
                    }
                } else {
                    ForEach(bars) { bar in
                        Annotation(bar.name, coordinate: CLLocationCoordinate2D(
                            latitude: bar.latitude, longitude: bar.longitude)) {
                            pin(for: bar).onTapGesture { onSelectBar(bar.id) }
                        }
                    }
                }
            }
            .mapStyle(.standard)
            .onTapGesture { pt in
                guard showOutlines, let coord = proxy.convert(pt, from: .local) else { return }
                if let hood = neighborhood(containing: coord) { onSelectNeighborhood(hood) }
            }
        }
        .onAppear { frame(animated: false) }
        .onChange(of: showOutlines) { _, _ in frame(animated: true) }
        .onChange(of: bars.map(\.id)) { _, _ in frame(animated: true) }
        .onChange(of: frameNonce) { _, _ in frame(animated: true) }
        .onMapCameraChange(frequency: .onEnd) { ctx in handleCameraChange(ctx.region) }
    }

    @ViewBuilder
    private func pin(for bar: Bar) -> some View {
        let visited = visitedIds.contains(bar.id)
        Text("🍸")
            .font(.system(size: 16))
            .frame(width: 36, height: 36)
            .background(Circle().fill(visited ? Palette.primary.opacity(0.4) : Palette.ink.opacity(0.8)))
            .overlay(Circle().strokeBorder(
                visited ? Palette.primary : Color.white.opacity(0.5), lineWidth: 2))
    }

    // MARK: - Framing

    private func frame(animated: Bool) {
        if suppressNextFrame { suppressNextFrame = false; return }
        // A neighborhood tap flips both `showOutlines` and `bars` in the same
        // update, firing frame() twice. Racing two animated camera sets in one
        // cycle can leave MapKit without fetching tiles (blank map until you
        // zoom). Coalesce: apply once on the next runloop, last request wins.
        frameGen &+= 1
        let gen = frameGen
        DispatchQueue.main.async {
            guard gen == frameGen else { return }
            let region = targetRegion()
            awaitingFrame = true
            let apply = { camera = .region(region) }
            if animated { withAnimation(.easeInOut(duration: 0.35)) { apply() } } else { apply() }
            // MapKit often lands on a programmatically-set region without
            // fetching tiles (blank/half-loaded map until you manually zoom).
            // After the move settles, apply an imperceptible span nudge — the
            // same kick a manual zoom gives — to force the tile loader to run.
            DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.45 : 0.1)) {
                guard gen == frameGen else { return }
                var r = region
                r.span.latitudeDelta *= 1.0015
                r.span.longitudeDelta *= 1.0015
                awaitingFrame = true
                camera = .region(r)
            }
        }
    }

    private func targetRegion() -> MKCoordinateRegion {
        let pts: [CLLocationCoordinate2D]
        if showOutlines || bars.isEmpty {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: AppData.region.latitude, longitude: AppData.region.longitude),
                span: MKCoordinateSpan(latitudeDelta: AppData.region.latitudeDelta, longitudeDelta: AppData.region.longitudeDelta))
        }
        pts = bars.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        let lats = pts.map(\.latitude), lons = pts.map(\.longitude)
        let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        // Floor the span so single-bar neighborhoods don't zoom so deep that
        // MapKit lands without tiles loaded.
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.025),
            longitudeDelta: max((maxLon - minLon) * 1.5, 0.025))
        return MKCoordinateRegion(center: center, span: span)
    }

    private func handleCameraChange(_ region: MKCoordinateRegion) {
        // First settle after a programmatic reframe: record the real rendered
        // span and don't treat it as a user zoom-out.
        if awaitingFrame {
            framedSpan = region.span.latitudeDelta
            awaitingFrame = false
            return
        }
        let r = Region(latitude: region.center.latitude, longitude: region.center.longitude,
                       latitudeDelta: region.span.latitudeDelta, longitudeDelta: region.span.longitudeDelta)
        // Zoomed out to span 2+ neighborhoods and 1.2x past the framed span.
        if Geo.fullyVisibleNeighborhoods(r) >= 2 && region.span.latitudeDelta > framedSpan * 1.2 {
            if onZoomOut() { suppressNextFrame = true }
        }
    }

    // MARK: - Hit testing

    private func neighborhood(containing coord: CLLocationCoordinate2D) -> String? {
        for name in AppData.neighborhoods {
            guard let ring = AppData.neighborhoodPolygons[name] else { continue }
            if pointInPolygon(coord, ring) { return name }
        }
        return nil
    }

    private func pointInPolygon(_ p: CLLocationCoordinate2D, _ ring: [LatLng]) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let xi = ring[i].longitude, yi = ring[i].latitude
            let xj = ring[j].longitude, yj = ring[j].latitude
            if (yi > p.latitude) != (yj > p.latitude),
               p.longitude < (xj - xi) * (p.latitude - yi) / (yj - yi) + xi {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}
