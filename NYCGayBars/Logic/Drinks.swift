import Foundation

/// Preset drink types offered in the drink logger. Users can also add custom ones.
let PRESET_DRINKS = ["Beer", "Cocktail", "Wine", "Shot", "Seltzer", "Non-alcoholic"]

private let DRINK_EMOJI: [String: String] = [
    "Beer": "🍺",
    "Cocktail": "🍸",
    "Wine": "🍷",
    "Shot": "🥃",
    "Seltzer": "🥤",
    "Non-alcoholic": "🧃",
]

/// Emoji shown next to a drink type. Falls back to a generic glass.
func drinkEmoji(_ type: String) -> String {
    DRINK_EMOJI[type] ?? "🍹"
}
