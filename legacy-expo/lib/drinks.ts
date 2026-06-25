/** Preset drink types offered in the drink logger. Users can also add custom ones. */
export const PRESET_DRINKS = [
  "Beer",
  "Cocktail",
  "Wine",
  "Shot",
  "Seltzer",
  "Non-alcoholic",
] as const;

export type PresetDrink = (typeof PRESET_DRINKS)[number];

/** Emoji shown next to each preset drink. Falls back to a generic glass. */
export const DRINK_EMOJI: Record<string, string> = {
  Beer: "🍺",
  Cocktail: "🍸",
  Wine: "🍷",
  Shot: "🥃",
  Seltzer: "🥤",
  "Non-alcoholic": "🧃",
};

export function drinkEmoji(type: string): string {
  return DRINK_EMOJI[type] ?? "🍹";
}
