import { BARS, NEIGHBORHOODS, getBarById } from "./bars";
import type { Bar, Visit } from "./types";
import { dayKey, dayKeyToDate, getDrinkTotal } from "./VisitsContext";

/** All-time drink count across every visit. */
export function totalDrinks(visits: Visit[]): number {
  return visits.reduce((sum, v) => sum + getDrinkTotal(v), 0);
}

/** Number of bar-days with at least one drink logged. */
export function totalDrinkDays(visits: Visit[]): number {
  return visits.length;
}

/** Longest run of consecutive days with at least one drink logged. */
export function longestDayStreak(visits: Visit[]): number {
  return longestRun(uniqueSortedDayTimes(visits));
}

/** Number of distinct bars with at least one drink logged. */
export function distinctBarsVisited(visits: Visit[]): number {
  return new Set(visits.map((v) => v.barId)).size;
}

/** Bar with the most drink-days, tiebroken by total drinks. */
export function favoriteBar(visits: Visit[]): Bar | undefined {
  const byBar = new Map<string, { days: number; drinks: number }>();
  for (const v of visits) {
    const cur = byBar.get(v.barId) ?? { days: 0, drinks: 0 };
    byBar.set(v.barId, {
      days: cur.days + 1,
      drinks: cur.drinks + getDrinkTotal(v),
    });
  }
  let bestId: string | undefined;
  let best = { days: 0, drinks: 0 };
  for (const [id, s] of byBar) {
    if (s.days > best.days || (s.days === best.days && s.drinks > best.drinks)) {
      bestId = id;
      best = s;
    }
  }
  return bestId ? getBarById(bestId) : undefined;
}

/** Most-logged drink type and its all-time count. */
export function topDrinkType(
  visits: Visit[],
): { type: string; count: number } | undefined {
  const counts = new Map<string, number>();
  for (const v of visits) {
    for (const d of v.drinks) {
      counts.set(d.type, (counts.get(d.type) ?? 0) + d.count);
    }
  }
  let best: { type: string; count: number } | undefined;
  for (const [type, count] of counts) {
    if (!best || count > best.count) best = { type, count };
  }
  return best;
}

/** The single day with the highest drink total. */
export function biggestNight(
  visits: Visit[],
): { day: string; total: number } | undefined {
  const byDay = new Map<string, number>();
  for (const v of visits) {
    const key = dayKey(v.date);
    byDay.set(key, (byDay.get(key) ?? 0) + getDrinkTotal(v));
  }
  let best: { day: string; total: number } | undefined;
  for (const [day, total] of byDay) {
    if (!best || total > best.total) best = { day, total };
  }
  return best;
}

/** Set of bar ids the user has ever visited (marked or drink-logged). */
export function computeVisitedIds(
  isVisited: (barId: string) => boolean,
): Set<string> {
  const ids = new Set<string>();
  for (const bar of BARS) {
    if (isVisited(bar.id)) ids.add(bar.id);
  }
  return ids;
}

export type NeighborhoodProgress = {
  neighborhood: string;
  visited: number;
  total: number;
};

/** Visited/total bar counts per neighborhood, most-complete first. */
export function neighborhoodProgress(
  visitedIds: Set<string>,
): NeighborhoodProgress[] {
  return NEIGHBORHOODS.map((neighborhood) => {
    const bars = BARS.filter((b) => b.neighborhood === neighborhood);
    return {
      neighborhood,
      visited: bars.filter((b) => visitedIds.has(b.id)).length,
      total: bars.length,
    };
  }).sort(
    (a, b) => b.visited / b.total - a.visited / a.total || b.visited - a.visited,
  );
}

export type Badge = {
  id: string;
  emoji: string;
  title: string;
  description: string;
  earned: boolean;
};

/**
 * Prestige badges whose unlock warrants a confetti celebration — the hard,
 * grind-y or completionist achievements rather than the easy early ones.
 */
export const MILESTONE_BADGE_IDS = new Set<string>([
  "full-week",
  "old-faithful",
  "nifty-fifty",
  "century-club",
  "explorer",
  "half-the-city",
  "neighborhood-hero",
  "grand-tour",
  "conqueror",
]);

/** Coarse borough for a neighborhood: the dataset's only non-Manhattan
 * neighborhoods are Brooklyn and Queens. */
function borough(neighborhood: string): string {
  return neighborhood === "Brooklyn" || neighborhood === "Queens"
    ? neighborhood
    : "Manhattan";
}

const DAY_MS = 24 * 60 * 60 * 1000;

/** The distinct visit days as sorted local-noon timestamps. */
function uniqueSortedDayTimes(visits: Visit[]): number[] {
  return [...new Set(visits.map((v) => dayKey(v.date)))]
    .map((k) => dayKeyToDate(k).getTime())
    .sort((a, b) => a - b);
}

/** Longest run of consecutive days among sorted local-noon timestamps. */
function longestRun(dayTimes: number[]): number {
  let best = dayTimes.length > 0 ? 1 : 0;
  let run = 1;
  for (let i = 1; i < dayTimes.length; i++) {
    // Noon-stamped dates, so DST shifts round away cleanly.
    if (Math.round((dayTimes[i] - dayTimes[i - 1]) / DAY_MS) === 1) {
      run++;
      best = Math.max(best, run);
    } else {
      run = 1;
    }
  }
  return best;
}

export function badges(visits: Visit[], visitedIds: Set<string>): Badge[] {
  const neighborhoodsVisited = new Set(
    [...visitedIds].map((id) => getBarById(id)?.neighborhood).filter(Boolean),
  ).size;

  const barsPerDay = new Map<string, Set<string>>();
  for (const v of visits) {
    const key = dayKey(v.date);
    const set = barsPerDay.get(key) ?? new Set<string>();
    set.add(v.barId);
    barsPerDay.set(key, set);
  }
  const maxBarsInOneDay = Math.max(
    0,
    ...[...barsPerDay.values()].map((s) => s.size),
  );

  const daysPerBar = new Map<string, number>();
  for (const v of visits) {
    daysPerBar.set(v.barId, (daysPerBar.get(v.barId) ?? 0) + 1);
  }
  const maxDaysAtOneBar = Math.max(0, ...daysPerBar.values());

  // All-time drink counts per type (case-insensitive).
  const drinkTotalsByType = new Map<string, number>();
  for (const v of visits) {
    for (const d of v.drinks) {
      const key = d.type.toLowerCase();
      drinkTotalsByType.set(key, (drinkTotalsByType.get(key) ?? 0) + d.count);
    }
  }
  const maxShotsInOneVisit = Math.max(
    0,
    ...visits.map(
      (v) => v.drinks.find((d) => d.type === "Shot")?.count ?? 0,
    ),
  );
  const maxTypesInOneVisit = Math.max(0, ...visits.map((v) => v.drinks.length));
  const boroughsVisited = new Set(
    [...visitedIds]
      .map((id) => getBarById(id)?.neighborhood)
      .filter((n): n is string => Boolean(n))
      .map(borough),
  );
  // Backdated visits are noon-stamped, so only live after-midnight logging
  // can produce an early-morning hour here.
  const hasLateNightVisit = visits.some(
    (v) => new Date(v.date).getHours() < 4,
  );

  // Weekdays (0=Sun…6=Sat) that have at least one visit. Backdated visits are
  // noon-stamped, so the local weekday is always the calendar day picked.
  const visitWeekdays = new Set(visits.map((v) => new Date(v.date).getDay()));

  const streak = longestDayStreak(visits);
  const maxDrinksInOneDay = biggestNight(visits)?.total ?? 0;

  // Longest consecutive-day run at a single bar.
  const visitsByBar = new Map<string, Visit[]>();
  for (const v of visits) {
    const list = visitsByBar.get(v.barId) ?? [];
    list.push(v);
    visitsByBar.set(v.barId, list);
  }
  const maxRunAtOneBar = Math.max(
    0,
    ...[...visitsByBar.values()].map((vs) =>
      longestRun(uniqueSortedDayTimes(vs)),
    ),
  );

  const hasCompleteNeighborhood = NEIGHBORHOODS.some((n) =>
    BARS.filter((b) => b.neighborhood === n).every((b) => visitedIds.has(b.id)),
  );

  return [
    {
      id: "first-drink",
      emoji: "🍻",
      title: "First Drink",
      description: "Log your first drink",
      earned: visits.length > 0,
    },
    {
      id: "stonewall",
      emoji: "🏳️‍🌈",
      title: "Stonewall Pilgrimage",
      description: "Visit The Stonewall Inn",
      earned: visitedIds.has("the-stonewall-inn"),
    },
    {
      id: "sampler",
      emoji: "🗺️",
      title: "Neighborhood Sampler",
      description: "Visit bars in 3 neighborhoods",
      earned: neighborhoodsVisited >= 3,
    },
    {
      id: "crawler",
      emoji: "🐛",
      title: "Bar Crawler",
      description: "Hit 3 bars in one day",
      earned: maxBarsInOneDay >= 3,
    },
    {
      id: "regular",
      emoji: "💺",
      title: "Regular",
      description: "5 drink-days at one bar",
      earned: maxDaysAtOneBar >= 5,
    },
    {
      id: "night-owl",
      emoji: "🦉",
      title: "Night Owl",
      description: "Log a drink after midnight",
      earned: hasLateNightVisit,
    },
    {
      id: "on-a-roll",
      emoji: "🔥",
      title: "On a Roll",
      description: "Drinks logged 3 days in a row",
      earned: streak >= 3,
    },
    {
      id: "mixologist",
      emoji: "🍹",
      title: "Mixologist",
      description: "Try 5 different drink types",
      earned: drinkTotalsByType.size >= 5,
    },
    {
      id: "shots-shots-shots",
      emoji: "🥃",
      title: "Shots Shots Shots",
      description: "3 shots in one visit",
      earned: maxShotsInOneVisit >= 3,
    },
    {
      id: "sober-curious",
      emoji: "🧃",
      title: "Sober Curious",
      description: "Log a non-alcoholic drink",
      earned: drinkTotalsByType.has("non-alcoholic"),
    },
    {
      id: "bar-star",
      emoji: "⭐",
      title: "Bar Star",
      description: "Visit 10 different bars",
      earned: visitedIds.size >= 10,
    },
    {
      id: "century-club",
      emoji: "💯",
      title: "Century Club",
      description: "100 drinks all-time",
      earned: totalDrinks(visits) >= 100,
    },
    {
      id: "borough-hopper",
      emoji: "🌉",
      title: "Borough Hopper",
      description: "Visit Manhattan, Brooklyn & Queens bars",
      earned: boroughsVisited.size >= 3,
    },
    {
      id: "marathon",
      emoji: "🏃",
      title: "Marathon",
      description: "Hit 5 bars in one day",
      earned: maxBarsInOneDay >= 5,
    },
    {
      id: "weekend-warrior",
      emoji: "🪩",
      title: "Weekend Warrior",
      description: "Log drinks on a Friday and a Saturday",
      earned: visitWeekdays.has(5) && visitWeekdays.has(6),
    },
    {
      id: "school-night",
      emoji: "📚",
      title: "School Night",
      description: "Log drinks on a weeknight (Mon–Thu)",
      earned: [1, 2, 3, 4].some((d) => visitWeekdays.has(d)),
    },
    {
      id: "full-week",
      emoji: "📅",
      title: "Full Week",
      description: "Drinks logged 7 days in a row",
      earned: streak >= 7,
    },
    {
      id: "back-to-back",
      emoji: "🔁",
      title: "Back to Back",
      description: "Same bar two days in a row",
      earned: maxRunAtOneBar >= 2,
    },
    {
      id: "old-faithful",
      emoji: "🪑",
      title: "Old Faithful",
      description: "10 drink-days at one bar",
      earned: maxDaysAtOneBar >= 10,
    },
    {
      id: "double-digits",
      emoji: "🔟",
      title: "Double Digits",
      description: "10 drinks in one day",
      earned: maxDrinksInOneDay >= 10,
    },
    {
      id: "nifty-fifty",
      emoji: "🏅",
      title: "Nifty Fifty",
      description: "50 drinks all-time",
      earned: totalDrinks(visits) >= 50,
    },
    {
      id: "hophead",
      emoji: "🍺",
      title: "Hophead",
      description: "25 beers all-time",
      earned: (drinkTotalsByType.get("beer") ?? 0) >= 25,
    },
    {
      id: "wine-not",
      emoji: "🍷",
      title: "Wine Not?",
      description: "10 wines all-time",
      earned: (drinkTotalsByType.get("wine") ?? 0) >= 10,
    },
    {
      id: "shaken-stirred",
      emoji: "🍸",
      title: "Shaken & Stirred",
      description: "25 cocktails all-time",
      earned: (drinkTotalsByType.get("cocktail") ?? 0) >= 25,
    },
    {
      id: "variety-pack",
      emoji: "🌈",
      title: "Variety Pack",
      description: "4 different drink types in one visit",
      earned: maxTypesInOneVisit >= 4,
    },
    {
      id: "explorer",
      emoji: "🧭",
      title: "Explorer",
      description: "Visit 25 different bars",
      earned: visitedIds.size >= 25,
    },
    {
      id: "half-the-city",
      emoji: "🗽",
      title: "Half the City",
      description: `Visit ${Math.ceil(BARS.length / 2)} bars`,
      earned: visitedIds.size >= Math.ceil(BARS.length / 2),
    },
    {
      id: "neighborhood-hero",
      emoji: "🏘️",
      title: "Neighborhood Hero",
      description: "Visit every bar in one neighborhood",
      earned: hasCompleteNeighborhood,
    },
    {
      id: "grand-tour",
      emoji: "🚇",
      title: "Grand Tour",
      description: "Visit a bar in every neighborhood",
      earned: neighborhoodsVisited === NEIGHBORHOODS.length,
    },
    {
      id: "conqueror",
      emoji: "👑",
      title: "Scene Conqueror",
      description: "Visit every bar in the city",
      earned: visitedIds.size === BARS.length,
    },
  ];
}
