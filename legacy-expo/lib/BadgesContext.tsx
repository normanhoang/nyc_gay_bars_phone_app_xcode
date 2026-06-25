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
import { success } from "./haptics";
import { badges, computeVisitedIds, type Badge } from "./stats";
import { useVisits } from "./VisitsContext";

// On-device storage key for badge first-earned timestamps.
const BADGE_DATES_KEY = "@gaybars/badgeDates";

/** How long each unlock toast stays on screen. */
const TOAST_MS = 3500;

export type BadgeWithDate = Badge & {
  /** ISO date-time of when the badge was first observed as earned. */
  earnedAt?: string;
};

type BadgesContextValue = {
  /** All badges in definition order, with earn dates where earned. */
  badges: BadgeWithDate[];
  /** Badges earned since app start, oldest first — drives the unlock toast. */
  unlocked: BadgeWithDate[];
  /** Drop the first badge from the unlock queue. */
  dismissUnlocked: () => void;
};

const BadgesContext = createContext<BadgesContextValue | undefined>(undefined);

export function BadgesProvider({ children }: { children: ReactNode }) {
  const { visits, hydrated: visitsHydrated, isVisited } = useVisits();
  const [earnedAt, setEarnedAt] = useState<Record<string, string>>({});
  const [unlocked, setUnlocked] = useState<BadgeWithDate[]>([]);
  const [hydrated, setHydrated] = useState(false);
  // The first reconcile stamps everything an existing user already earned —
  // it must not produce a toast storm. Restores are silent too.
  const firstReconcile = useRef(true);

  // Load badge earn dates from on-device storage on mount.
  useEffect(() => {
    let active = true;

    (async () => {
      try {
        const raw = await AsyncStorage.getItem(BADGE_DATES_KEY);
        if (!active) return;
        if (raw) setEarnedAt(JSON.parse(raw) as Record<string, string>);
      } catch (e) {
        console.warn("Failed to load badge dates from storage", e);
      } finally {
        if (active) setHydrated(true);
      }
    })();

    return () => {
      active = false;
    };
  }, []);

  // Persist earn dates on change, after the initial load.
  useEffect(() => {
    if (!hydrated) return;
    AsyncStorage.setItem(BADGE_DATES_KEY, JSON.stringify(earnedAt)).catch((e) =>
      console.warn("Failed to save badge dates", e),
    );
  }, [earnedAt, hydrated]);

  const visitedIds = useMemo(() => computeVisitedIds(isVisited), [isVisited]);
  const allBadges = useMemo(
    () => badges(visits, visitedIds),
    [visits, visitedIds],
  );

  // Reconcile earn dates with the computed badge states: stamp newly earned
  // badges (queuing them for the unlock toast), drop stamps for badges that
  // reverted (e.g. history cleared). The persist effect saves earnedAt.
  useEffect(() => {
    if (!hydrated || !visitsHydrated) return;
    let changed = false;
    const next = { ...earnedAt };
    const newly: Badge[] = [];

    for (const b of allBadges) {
      if (b.earned && !next[b.id]) {
        next[b.id] = new Date().toISOString();
        newly.push(b);
        changed = true;
      } else if (!b.earned && next[b.id]) {
        delete next[b.id];
        changed = true;
      }
    }

    if (changed) setEarnedAt(next);

    if (newly.length > 0 && !firstReconcile.current) {
      setUnlocked((prev) => {
        const queued = new Set(prev.map((b) => b.id));
        const add = newly
          .filter((b) => !queued.has(b.id))
          .map((b) => ({ ...b, earnedAt: next[b.id] }));
        if (add.length) success();
        return add.length ? [...prev, ...add] : prev;
      });
    }

    firstReconcile.current = false;
  }, [hydrated, visitsHydrated, allBadges, earnedAt]);

  // Auto-advance the unlock toast queue. Lives here (not in the toast
  // component) so BadgeToast can be mounted in several places safely.
  useEffect(() => {
    if (unlocked.length === 0) return;
    const timer = setTimeout(
      () => setUnlocked((prev) => prev.slice(1)),
      TOAST_MS,
    );
    return () => clearTimeout(timer);
  }, [unlocked]);

  const dismissUnlocked = useCallback(() => {
    setUnlocked((prev) => prev.slice(1));
  }, []);

  const value = useMemo<BadgesContextValue>(
    () => ({
      badges: allBadges.map((b) => ({ ...b, earnedAt: earnedAt[b.id] })),
      unlocked,
      dismissUnlocked,
    }),
    [allBadges, earnedAt, unlocked, dismissUnlocked],
  );

  return (
    <BadgesContext.Provider value={value}>{children}</BadgesContext.Provider>
  );
}

export function useBadges(): BadgesContextValue {
  const ctx = useContext(BadgesContext);
  if (!ctx) throw new Error("useBadges must be used within a BadgesProvider");
  return ctx;
}
