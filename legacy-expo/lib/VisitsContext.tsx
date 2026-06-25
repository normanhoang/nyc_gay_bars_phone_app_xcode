import AsyncStorage from "@react-native-async-storage/async-storage";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import type { Visit } from "./types";

// On-device storage keys for visits and "been here" flags.
const VISITS_KEY = "@gaybars/visits";
const VISITED_KEY = "@gaybars/visited";

type VisitsContextValue = {
  /** All visits, most recent first. */
  visits: Visit[];
  /** Bars manually marked "I've been here" (drink-logged bars not included). */
  visitedBars: string[];
  /** True until the persisted state has been loaded from local storage. */
  hydrated: boolean;
  /** Log a drink at a bar. `day` is a dayKey; defaults to today. */
  logDrink: (barId: string, type: string, day?: string) => void;
  removeDrink: (barId: string, type: string, day?: string) => void;
  /** A bar's visit on a given day (default today), or undefined if none. */
  getVisitFor: (barId: string, day?: string) => Visit | undefined;
  /** Set/clear the note on a bar's visit for a day; no-op without a visit. */
  setVisitNote: (barId: string, day: string, note: string) => void;
  getVisitsForBar: (barId: string) => Visit[];
  /** All visits on a given local day (see dayKey), most recent first. */
  getVisitsForDay: (day: string) => Visit[];
  clearVisit: (visitId: string) => void;
  /** Clear logged drink history. If includeVisited, also wipe all-time visited marks. */
  clearHistory: (includeVisited: boolean) => void;
  /** All-time "I've been here" flag (true if marked or any drink logged). */
  isVisited: (barId: string) => boolean;
  /**
   * Toggle the visited flag. Setting true also records a zero-drink "check-in"
   * visit for `day` (default today) so the bar shows on that day's calendar
   * even with no drinks. Setting false clears the bar's drink-days.
   */
  setVisited: (barId: string, visited: boolean, day?: string) => void;
};

const VisitsContext = createContext<VisitsContextValue | undefined>(undefined);

/** Local day identifier (YYYY-M-D) so "a day" follows the user's calendar. */
export function dayKey(date: Date | string = new Date()): string {
  const d = typeof date === "string" ? new Date(date) : date;
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
}

/** Noon local time on the given day, so the ISO string round-trips dayKey. */
export function dayKeyToDate(key: string): Date {
  const [y, m, d] = key.split("-").map(Number);
  return new Date(y, m, d, 12);
}

/** Human-readable form of a dayKey, e.g. "Tuesday, June 9, 2026". */
export function formatDayKey(key: string): string {
  return dayKeyToDate(key).toLocaleDateString(undefined, {
    weekday: "long",
    month: "long",
    day: "numeric",
    year: "numeric",
  });
}

function isFutureDay(key: string): boolean {
  return dayKeyToDate(key).getTime() > dayKeyToDate(dayKey()).getTime();
}

function makeId(): string {
  return `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

export function VisitsProvider({ children }: { children: ReactNode }) {
  const [visits, setVisits] = useState<Visit[]>([]);
  const [visitedBars, setVisitedBars] = useState<string[]>([]);
  const [hydrated, setHydrated] = useState(false);

  // Refs let callbacks read current state without stale closures.
  const visitsRef = useRef<Visit[]>([]);
  visitsRef.current = visits;
  const visitedBarsRef = useRef<string[]>([]);
  visitedBarsRef.current = visitedBars;

  // Load persisted state from on-device storage on mount.
  useEffect(() => {
    let active = true;

    (async () => {
      try {
        const [rawVisits, rawVisited] = await AsyncStorage.multiGet([
          VISITS_KEY,
          VISITED_KEY,
        ]).then((pairs) => pairs.map(([, v]) => v));

        if (!active) return;
        setVisits(rawVisits ? (JSON.parse(rawVisits) as Visit[]) : []);
        setVisitedBars(rawVisited ? (JSON.parse(rawVisited) as string[]) : []);
      } catch (e) {
        console.warn("Failed to load visits from storage", e);
      } finally {
        if (active) setHydrated(true);
      }
    })();

    return () => {
      active = false;
    };
  }, []);

  // Persist on change, but only after the initial load so we never overwrite
  // stored data with the empty starting state.
  useEffect(() => {
    if (!hydrated) return;
    AsyncStorage.setItem(VISITS_KEY, JSON.stringify(visits)).catch((e) =>
      console.warn("Failed to save visits", e),
    );
  }, [visits, hydrated]);

  useEffect(() => {
    if (!hydrated) return;
    AsyncStorage.setItem(VISITED_KEY, JSON.stringify(visitedBars)).catch((e) =>
      console.warn("Failed to save visited bars", e),
    );
  }, [visitedBars, hydrated]);

  const logDrink = useCallback(
    (barId: string, rawType: string, day?: string) => {
      const type = rawType.trim();
      if (!type) return;
      const targetDay = day ?? dayKey();
      if (isFutureDay(targetDay)) return;

      const existing = visitsRef.current.find(
        (v) => v.barId === barId && dayKey(v.date) === targetDay,
      );

      let newVisit: Visit;
      if (!existing) {
        newVisit = {
          id: makeId(),
          barId,
          date:
            targetDay === dayKey()
              ? new Date().toISOString()
              : dayKeyToDate(targetDay).toISOString(),
          drinks: [{ type, count: 1 }],
        };
        setVisits((prev) => [newVisit, ...prev]);
      } else {
        const drinks = [...existing.drinks];
        const di = drinks.findIndex(
          (d) => d.type.toLowerCase() === type.toLowerCase(),
        );
        if (di === -1) drinks.push({ type, count: 1 });
        else drinks[di] = { ...drinks[di], count: drinks[di].count + 1 };
        newVisit = { ...existing, drinks };
        setVisits((prev) =>
          prev.map((v) => (v.id === existing.id ? newVisit : v)),
        );
      }
    },
    [],
  );

  const removeDrink = useCallback(
    (barId: string, rawType: string, day?: string) => {
      const type = rawType.trim();
      if (!type) return;
      const targetDay = day ?? dayKey();

      const existing = visitsRef.current.find(
        (v) => v.barId === barId && dayKey(v.date) === targetDay,
      );
      if (!existing) return;

      const di = existing.drinks.findIndex(
        (d) => d.type.toLowerCase() === type.toLowerCase(),
      );
      if (di === -1) return;

      const drinks = [...existing.drinks];
      const nextCount = drinks[di].count - 1;
      if (nextCount <= 0) drinks.splice(di, 1);
      else drinks[di] = { ...drinks[di], count: nextCount };

      if (drinks.length === 0) {
        setVisits((prev) => prev.filter((v) => v.id !== existing.id));
      } else {
        const updated = { ...existing, drinks };
        setVisits((prev) =>
          prev.map((v) => (v.id === existing.id ? updated : v)),
        );
      }
    },
    [],
  );

  const getVisitFor = useCallback(
    (barId: string, day: string = dayKey()) =>
      visits.find((v) => v.barId === barId && dayKey(v.date) === day),
    [visits],
  );

  const setVisitNote = useCallback(
    (barId: string, day: string, rawNote: string) => {
      const note = rawNote.trim();
      const existing = visitsRef.current.find(
        (v) => v.barId === barId && dayKey(v.date) === day,
      );
      if (!existing) return;
      if ((existing.note ?? "") === note) return;

      let updated: Visit;
      if (note) {
        updated = { ...existing, note };
      } else {
        const { note: _removed, ...rest } = existing;
        updated = rest;
      }
      setVisits((prev) =>
        prev.map((v) => (v.id === existing.id ? updated : v)),
      );
    },
    [],
  );

  const getVisitsForBar = useCallback(
    (barId: string) => visits.filter((v) => v.barId === barId),
    [visits],
  );

  const getVisitsForDay = useCallback(
    (day: string) => visits.filter((v) => dayKey(v.date) === day),
    [visits],
  );

  const clearVisit = useCallback((visitId: string) => {
    setVisits((prev) => prev.filter((v) => v.id !== visitId));
  }, []);

  const clearHistory = useCallback((includeVisited: boolean) => {
    setVisits([]);
    if (includeVisited) setVisitedBars([]);
  }, []);

  // Closes over state (not the refs) so its identity changes with the data —
  // consumers memoize computeVisitedIds(isVisited) keyed on this function.
  const isVisited = useCallback(
    (barId: string) =>
      visitedBars.includes(barId) || visits.some((v) => v.barId === barId),
    [visitedBars, visits],
  );

  const setVisited = useCallback(
    (barId: string, visited: boolean, day?: string) => {
      if (visited) {
        setVisitedBars((prev) =>
          prev.includes(barId) ? prev : [...prev, barId],
        );

        // Record a zero-drink check-in so the day shows on the calendar.
        const targetDay = day ?? dayKey();
        const existing = visitsRef.current.find(
          (v) => v.barId === barId && dayKey(v.date) === targetDay,
        );
        if (!existing && !isFutureDay(targetDay)) {
          const checkIn: Visit = {
            id: makeId(),
            barId,
            date:
              targetDay === dayKey()
                ? new Date().toISOString()
                : dayKeyToDate(targetDay).toISOString(),
            drinks: [],
          };
          setVisits((prev) => [checkIn, ...prev]);
        }
      } else {
        setVisitedBars((prev) => prev.filter((id) => id !== barId));
        setVisits((prev) => prev.filter((v) => v.barId !== barId));
      }
    },
    [],
  );

  const value = useMemo<VisitsContextValue>(
    () => ({
      visits,
      visitedBars,
      hydrated,
      logDrink,
      removeDrink,
      getVisitFor,
      setVisitNote,
      getVisitsForBar,
      getVisitsForDay,
      clearVisit,
      clearHistory,
      isVisited,
      setVisited,
    }),
    [
      visits,
      visitedBars,
      hydrated,
      logDrink,
      removeDrink,
      getVisitFor,
      setVisitNote,
      getVisitsForBar,
      getVisitsForDay,
      clearVisit,
      clearHistory,
      isVisited,
      setVisited,
    ],
  );

  return (
    <VisitsContext.Provider value={value}>{children}</VisitsContext.Provider>
  );
}

export function useVisits(): VisitsContextValue {
  const ctx = useContext(VisitsContext);
  if (!ctx) throw new Error("useVisits must be used within a VisitsProvider");
  return ctx;
}

/** Total number of drinks across all types in a visit. */
export function getDrinkTotal(visit: Visit): number {
  return visit.drinks.reduce((sum, d) => sum + d.count, 0);
}
