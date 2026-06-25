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
    /// Bumped on every frame() request so coalesced async applies keep only the last.
    @State private var frameGen = 0
    /// While we're driving the camera, suppress the zoom-out→All check. `framedSpan`
    /// keeps tracking the rendered span during this window so it ends pinned to the
    /// settled target (MapKit may enlarge a region to fit wide/non-square bars).
    @State private var framingUntil = Date.distantPast

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
        // update, firing frame() twice. Coalesce: apply once on the next
        // runloop, last request wins.
        frameGen &+= 1
        let gen = frameGen
        DispatchQueue.main.async {
            guard gen == frameGen else { return }
            let region = targetRegion()
            framingUntil = Date().addingTimeInterval(1.3)
            guard animated else { camera = .region(region); return }
            // MapKit often lands on a single programmatically-set region without
            // fetching tiles (blank/half-loaded map). Prime the tiles *before*
            // the zoom: snap to a zoomed-out view of the target first (a discrete
            // camera set kicks the tile loader), then animate in to the exact
            // region. The animation ends at the target, so there's zero tail
            // motion / no post-settle jump.
            var wide = region
            wide.span.latitudeDelta *= 2.5
            wide.span.longitudeDelta *= 2.5
            camera = .region(wide)
            DispatchQueue.main.async {
                guard gen == frameGen else { return }
                withAnimation(.easeInOut(duration: 0.45)) { camera = .region(region) }
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
        // While we're driving the camera (prime + zoom-in), keep recording the
        // rendered span but don't treat it as a user zoom-out. After the window
        // closes, framedSpan is pinned to the settled target span.
        if Date() < framingUntil {
            framedSpan = region.span.latitudeDelta
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
