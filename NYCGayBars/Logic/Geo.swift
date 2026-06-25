import Foundation

/// Geolocation helpers ported from RN lib/geo.ts.
enum Geo {
    private static let milesPerDegLat = 69.0

    /// Squared equirectangular distance — fine for ranking, not metric.
    private static func sqDist(_ lat: Double, _ lng: Double, _ bar: Bar, _ latRadCos: Double) -> Double {
        let dLat = bar.latitude - lat
        let dLon = (bar.longitude - lng) * latRadCos
        return dLat * dLat + dLon * dLon
    }

    struct Bounds { var minLat, maxLat, minLon, maxLon: Double }

    /// Bounding box of each neighborhood's bars, computed once from BARS.
    static let neighborhoodBounds: [String: Bounds] = {
        var bounds: [String: Bounds] = [:]
        for bar in AppData.bars {
            if var b = bounds[bar.neighborhood] {
                b.minLat = min(b.minLat, bar.latitude)
                b.maxLat = max(b.maxLat, bar.latitude)
                b.minLon = min(b.minLon, bar.longitude)
                b.maxLon = max(b.maxLon, bar.longitude)
                bounds[bar.neighborhood] = b
            } else {
                bounds[bar.neighborhood] = Bounds(
                    minLat: bar.latitude, maxLat: bar.latitude,
                    minLon: bar.longitude, maxLon: bar.longitude)
            }
        }
        return bounds
    }()

    /// How many neighborhoods sit entirely inside the visible map region.
    static func fullyVisibleNeighborhoods(_ region: Region) -> Int {
        let minLat = region.latitude - region.latitudeDelta / 2
        let maxLat = region.latitude + region.latitudeDelta / 2
        let minLon = region.longitude - region.longitudeDelta / 2
        let maxLon = region.longitude + region.longitudeDelta / 2
        var count = 0
        for b in neighborhoodBounds.values {
            if b.minLat >= minLat && b.maxLat <= maxLat && b.minLon >= minLon && b.maxLon <= maxLon {
                count += 1
            }
        }
        return count
    }

    /// Equirectangular distance in miles — accurate enough at city scale.
    static func distanceMiles(_ lat: Double, _ lng: Double, _ bar: Bar) -> Double {
        let cos = Foundation.cos(lat * .pi / 180)
        return sqrt(sqDist(lat, lng, bar, cos)) * milesPerDegLat
    }

    /// The bar closest to the given coordinates.
    static func nearestBar(_ latitude: Double, _ longitude: Double) -> Bar {
        let cos = Foundation.cos(latitude * .pi / 180)
        var best = AppData.bars[0]
        var bestDist = Double.infinity
        for bar in AppData.bars {
            let dist = sqDist(latitude, longitude, bar, cos)
            if dist < bestDist { bestDist = dist; best = bar }
        }
        return best
    }

    /// Neighborhoods ordered by how close their nearest bar is (closest first).
    static func neighborhoodsByProximity(_ latitude: Double, _ longitude: Double) -> [String] {
        let cos = Foundation.cos(latitude * .pi / 180)
        var minDist: [String: Double] = [:]
        for bar in AppData.bars {
            let dist = sqDist(latitude, longitude, bar, cos)
            if let cur = minDist[bar.neighborhood] {
                if dist < cur { minDist[bar.neighborhood] = dist }
            } else {
                minDist[bar.neighborhood] = dist
            }
        }
        return AppData.neighborhoods.sorted {
            (minDist[$0] ?? .infinity) < (minDist[$1] ?? .infinity)
        }
    }

    /// True when the string is a 5-digit ZIP code in our NYC dataset.
    static func isKnownZip(_ query: String) -> Bool {
        guard query.count == 5, query.allSatisfy({ $0.isNumber }) else { return false }
        return AppData.zipCentroids[query] != nil
    }

    /// The bar neighborhood closest to a NYC ZIP's centroid, or nil if unknown.
    static func neighborhoodForZip(_ zip: String) -> String? {
        guard isKnownZip(zip), let c = AppData.zipCentroids[zip] else { return nil }
        return nearestBar(c.lat, c.lng).neighborhood
    }
}
