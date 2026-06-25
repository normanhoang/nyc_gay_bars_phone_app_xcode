import type { Visit } from "../types";
import { dayKeyToDate } from "../VisitsContext";
import {
  badges,
  biggestNight,
  distinctBarsVisited,
  favoriteBar,
  longestDayStreak,
  neighborhoodProgress,
  topDrinkType,
  totalDrinkDays,
  totalDrinks,
} from "../stats";

let nextId = 1;

/** A visit on a local day key ("2026-5-9" = June 9 2026) with given drinks. */
function visit(
  barId: string,
  day: string,
  drinks: Record<string, number> = { Beer: 1 },
): Visit {
  return {
    id: `v${nextId++}`,
    barId,
    date: dayKeyToDate(day).toISOString(),
    drinks: Object.entries(drinks).map(([type, count]) => ({ type, count })),
  };
}

describe("totals", () => {
  it("counts drinks across visits and types", () => {
    const visits = [
      visit("a", "2026-5-1", { Beer: 2, Shot: 1 }),
      visit("b", "2026-5-2", { Wine: 3 }),
    ];
    expect(totalDrinks(visits)).toBe(6);
    expect(totalDrinkDays(visits)).toBe(2);
    expect(distinctBarsVisited(visits)).toBe(2);
  });
});

describe("longestDayStreak", () => {
  it("is 0 with no visits and 1 for a single day", () => {
    expect(longestDayStreak([])).toBe(0);
    expect(longestDayStreak([visit("a", "2026-5-9")])).toBe(1);
  });

  it("counts consecutive days and ignores gaps", () => {
    const visits = [
      visit("a", "2026-5-1"),
      visit("b", "2026-5-2"), // different bar still extends the day streak
      visit("a", "2026-5-3"),
      visit("a", "2026-5-7"), // gap — new run
      visit("a", "2026-5-8"),
    ];
    expect(longestDayStreak(visits)).toBe(3);
  });

  it("dedupes multiple visits on the same day", () => {
    const visits = [
      visit("a", "2026-5-1"),
      visit("b", "2026-5-1"),
      visit("a", "2026-5-2"),
    ];
    expect(longestDayStreak(visits)).toBe(2);
  });

  it("spans a month boundary", () => {
    // 2026-4-31 is May 31; 2026-5-1 is June 1 (dayKey months are 0-based).
    expect(
      longestDayStreak([visit("a", "2026-4-31"), visit("a", "2026-5-1")]),
    ).toBe(2);
  });
});

describe("favoriteBar", () => {
  it("prefers more drink-days, then more drinks", () => {
    const visits = [
      visit("eagle-nyc", "2026-5-1"),
      visit("eagle-nyc", "2026-5-2"),
      visit("the-monster", "2026-5-3", { Beer: 10 }),
    ];
    expect(favoriteBar(visits)?.id).toBe("eagle-nyc");

    const tied = [
      visit("eagle-nyc", "2026-5-1", { Beer: 1 }),
      visit("the-monster", "2026-5-2", { Beer: 5 }),
    ];
    expect(favoriteBar(tied)?.id).toBe("the-monster");
  });

  it("is undefined with no visits", () => {
    expect(favoriteBar([])).toBeUndefined();
  });
});

describe("topDrinkType / biggestNight", () => {
  it("finds the most-logged type", () => {
    const visits = [
      visit("a", "2026-5-1", { Beer: 2, Shot: 3 }),
      visit("b", "2026-5-2", { Shot: 1 }),
    ];
    expect(topDrinkType(visits)).toEqual({ type: "Shot", count: 4 });
  });

  it("sums a day across bars for the biggest night", () => {
    const visits = [
      visit("a", "2026-5-1", { Beer: 2 }),
      visit("b", "2026-5-1", { Shot: 3 }),
      visit("a", "2026-5-2", { Beer: 4 }),
    ];
    expect(biggestNight(visits)).toEqual({ day: "2026-5-1", total: 5 });
  });
});

describe("neighborhoodProgress", () => {
  it("covers all 11 neighborhoods and counts visited bars", () => {
    const progress = neighborhoodProgress(new Set(["eagle-nyc"]));
    expect(progress).toHaveLength(11);
    const chelsea = progress.find((p) => p.neighborhood === "Chelsea");
    expect(chelsea?.visited).toBe(1);
    expect(chelsea && chelsea.total > 1).toBe(true);
  });
});

describe("badges", () => {
  const none = badges([], new Set());

  it("returns exactly 30 badges, all unearned with no data", () => {
    expect(none).toHaveLength(30);
    expect(none.every((b) => !b.earned)).toBe(true);
    expect(new Set(none.map((b) => b.id)).size).toBe(30);
  });

  function earned(visits: Visit[], visitedIds: Set<string> = new Set()) {
    const all = badges(
      visits,
      // visitedIds implied by visits, like computeVisitedIds would produce
      new Set([...visitedIds, ...visits.map((v) => v.barId)]),
    );
    return new Set(all.filter((b) => b.earned).map((b) => b.id));
  }

  it("first-drink on any visit", () => {
    expect(earned([visit("a", "2026-5-1")]).has("first-drink")).toBe(true);
  });

  it("on-a-roll at 3 consecutive days, full-week at 7", () => {
    const threeDays = ["2026-5-1", "2026-5-2", "2026-5-3"].map((d) =>
      visit("a", d),
    );
    expect(earned(threeDays).has("on-a-roll")).toBe(true);
    expect(earned(threeDays).has("full-week")).toBe(false);

    const week = [1, 2, 3, 4, 5, 6, 7].map((d) => visit("a", `2026-5-${d}`));
    expect(earned(week).has("full-week")).toBe(true);
  });

  it("back-to-back needs the same bar on consecutive days", () => {
    const differentBars = [visit("a", "2026-5-1"), visit("b", "2026-5-2")];
    expect(earned(differentBars).has("back-to-back")).toBe(false);
    const sameBar = [visit("a", "2026-5-1"), visit("a", "2026-5-2")];
    expect(earned(sameBar).has("back-to-back")).toBe(true);
  });

  it("century-club at 100 drinks", () => {
    expect(
      earned([visit("a", "2026-5-1", { Beer: 99 })]).has("century-club"),
    ).toBe(false);
    expect(
      earned([visit("a", "2026-5-1", { Beer: 100 })]).has("century-club"),
    ).toBe(true);
  });

  it("variety-pack at 4 drink types in one visit", () => {
    const v = visit("a", "2026-5-1", { Beer: 1, Wine: 1, Shot: 1, Seltzer: 1 });
    expect(earned([v]).has("variety-pack")).toBe(true);
  });

  it("borough-hopper needs Manhattan, Brooklyn and Queens", () => {
    const two = earned([], new Set(["eagle-nyc", "metropolitan"]));
    expect(two.has("borough-hopper")).toBe(false);
    const three = earned([], new Set(["eagle-nyc", "metropolitan", "icon-bar"]));
    expect(three.has("borough-hopper")).toBe(true);
  });

  it("stonewall pilgrimage via visited flag alone", () => {
    expect(
      earned([], new Set(["the-stonewall-inn"])).has("stonewall"),
    ).toBe(true);
  });

  it("night-owl is immune to noon-stamped backdated visits", () => {
    // Backdated visits are noon local time — never counts as late-night.
    expect(earned([visit("a", "2026-5-1")]).has("night-owl")).toBe(false);

    const lateNight: Visit = {
      id: "ln",
      barId: "a",
      date: new Date(2026, 5, 1, 1, 30).toISOString(), // 1:30am local
      drinks: [{ type: "Beer", count: 1 }],
    };
    expect(earned([lateNight]).has("night-owl")).toBe(true);
  });
});
