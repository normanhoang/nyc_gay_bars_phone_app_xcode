import Foundation

/// A point on a neighborhood outline polygon.
struct LatLng: Codable, Hashable {
    let latitude: Double
    let longitude: Double
}

/// A NYC ZIP code centroid.
struct ZipCentroid: Codable {
    let lat: Double
    let lng: Double
}

/// Map region that comfortably frames all NYC bars.
struct Region: Codable {
    let latitude: Double
    let longitude: Double
    let latitudeDelta: Double
    let longitudeDelta: Double
}

private struct Meta: Codable {
    let neighborhoods: [String]
    let region: Region
}

/// Static, build-time-generated dataset loaded from bundled JSON. Mirrors the
/// RN app's lib/bars.ts, lib/neighborhoods.ts, lib/zips.ts (all generated). No
/// runtime network or map API key is needed.
enum AppData {
    static let bars: [Bar] = load("bars")
    static let neighborhoodPolygons: [String: [LatLng]] = load("neighborhoods")
    static let zipCentroids: [String: ZipCentroid] = load("zips")

    private static let meta: Meta = load("meta")
    /// Unique neighborhoods present in BARS, sorted — drives the filter UI.
    static var neighborhoods: [String] { meta.neighborhoods }
    /// Map region that frames all NYC bars.
    static var region: Region { meta.region }

    static func bar(id: String) -> Bar? { bars.first { $0.id == id } }

    private static func load<T: Decodable>(_ name: String) -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("Missing bundled resource \(name).json")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            fatalError("Failed to decode \(name).json: \(error)")
        }
    }
}
