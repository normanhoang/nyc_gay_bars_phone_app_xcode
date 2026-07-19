import Foundation

/// Preset drink types offered in the drink logger. Users can also add custom ones.
let PRESET_DRINKS = ["Beer", "Cocktail", "Wine", "Shot", "Seltzer", "Non-alcoholic"]

private let DRINK_EMOJI: [String: String] = [
    "beer": "🍺",
    "cocktail": "🍸",
    "wine": "🍷",
    "shot": "🥃",
    "seltzer": "🥤",
    "non-alcoholic": "🧃",
]

/// Emoji shown next to a drink type (case-insensitive, so a custom-typed
/// "beer" matches the preset). Falls back to a generic glass.
func drinkEmoji(_ type: String) -> String {
    DRINK_EMOJI[type.lowercased()] ?? "🍹"
}
