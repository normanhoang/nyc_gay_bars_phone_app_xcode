export type Bar = {
  id: string;
  name: string;
  /** e.g. "Hell's Kitchen", "West Village", "Brooklyn" */
  neighborhood: string;
  address: string;
  latitude: number;
  longitude: number;
  description?: string;
  /** Curated vibe tags, e.g. "dive", "drag", "leather", "piano". */
  tags?: string[];
};

/** A drink type and how many of it were had during a visit. */
export type DrinkEntry = {
  /** Preset name (e.g. "Beer") or a free-form custom name (e.g. "Margarita"). */
  type: string;
  count: number;
};

/** A single day's visit to a bar, with the drinks had aggregated per type. */
export type Visit = {
  id: string;
  barId: string;
  /** ISO date-time of when the visit was first logged. */
  date: string;
  drinks: DrinkEntry[];
  /** Free-form note about the night. */
  note?: string;
};
