import Foundation

/// A NYC gay bar from the curated, pre-geocoded dataset.
struct Bar: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    /// e.g. "Hell's Kitchen", "West Village", "Brooklyn"
    let neighborhood: String
    let address: String
    let latitude: Double
    let longitude: Double
    var description: String?
    /// Curated vibe tags, e.g. "dive", "drag", "leather", "piano".
    var tags: [String]?
}

/// A drink type and how many of it were had during a visit.
struct DrinkEntry: Codable, Hashable {
    /// Preset name (e.g. "Beer") or a free-form custom name (e.g. "Margarita").
    let type: String
    var count: Int
}

/// A single day's visit to a bar, with the drinks had aggregated per type.
struct Visit: Codable, Identifiable, Hashable {
    let id: String
    let barId: String
    /// ISO date-time of when the visit was first logged.
    let date: String
    var drinks: [DrinkEntry]
    /// Free-form note about the night.
    var note: String?

    /// Total number of drinks across all types in this visit.
    var drinkTotal: Int { drinks.reduce(0) { $0 + $1.count } }
}

/// A badge definition with its earned state; `earnedAt` set when first observed.
struct Badge: Identifiable, Hashable {
    let id: String
    let emoji: String
    let title: String
    let description: String
    let earned: Bool
    var earnedAt: String?
}
