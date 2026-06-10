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
import { supabase } from "./supabase";
import { useVisits } from "./VisitsContext";

// Legacy AsyncStorage key — only used once to migrate pre-Supabase installs.
const LEGACY_BADGE_DATES_KEY = "@gaybars/badgeDates";

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

export function BadgesProvider({
  children,
  userId,
}: {
  children: ReactNode;
  userId: string;
}) {
  const { visits, hydrated: visitsHydrated, isVisited } = useVisits();
  const [earnedAt, setEarnedAt] = useState<Record<string, string>>({});
  const [unlocked, setUnlocked] = useState<BadgeWithDate[]>([]);
  const [hydrated, setHydrated] = useState(false);
  // The first reconcile stamps everything an existing user already earned —
  // it must not produce a toast storm. Restores are silent too.
  const firstReconcile = useRef(true);

  // Load badge earn dates from Supabase. If Supabase is empty and AsyncStorage
  // has data (pre-Supabase install), migrate it then clear legacy storage.
  useEffect(() => {
    let active = true;
    setHydrated(false);
    setEarnedAt({});

    (async () => {
      try {
        const { data } = await supabase
          .from("badge_dates")
          .select("badge_id, earned_at")
          .eq("user_id", userId);

        if (!active) return;

        if (data && data.length > 0) {
          const map: Record<string, string> = {};
          data.forEach((row) => {
            map[row.badge_id as string] = row.earned_at as string;
          });
          setEarnedAt(map);
        } else {
          // First-time sign-in: migrate any locally stored badge dates.
          const raw = await AsyncStorage.getItem(LEGACY_BADGE_DATES_KEY);
          if (raw) {
            const localMap = JSON.parse(raw) as Record<string, string>;
            const entries = Object.entries(localMap);
            if (entries.length > 0) {
              await supabase.from("badge_dates").insert(
                entries.map(([badge_id, earned_at]) => ({
                  user_id: userId,
                  badge_id,
                  earned_at,
                })),
              );
              await AsyncStorage.removeItem(LEGACY_BADGE_DATES_KEY);
              if (!active) return;
              setEarnedAt(localMap);
            }
          }
        }
      } catch (e) {
        console.warn("Failed to load badge dates from Supabase", e);
      } finally {
        if (active) setHydrated(true);
      }
    })();

    return () => {
      active = false;
    };
  }, [userId]);

  const visitedIds = useMemo(() => computeVisitedIds(isVisited), [isVisited]);
  const allBadges = useMemo(
    () => badges(visits, visitedIds),
    [visits, visitedIds],
  );

  // Reconcile earn dates with the computed badge states: stamp newly earned
  // badges (queuing them for the unlock toast), drop stamps for badges that
  // reverted (e.g. history cleared). Write deltas directly to Supabase.
  useEffect(() => {
    if (!hydrated || !visitsHydrated) return;
    let changed = false;
    const next = { ...earnedAt };
    const newly: Badge[] = [];
    const removed: string[] = [];

    for (const b of allBadges) {
      if (b.earned && !next[b.id]) {
        next[b.id] = new Date().toISOString();
        newly.push(b);
        changed = true;
      } else if (!b.earned && next[b.id]) {
        removed.push(b.id);
        delete next[b.id];
        changed = true;
      }
    }

    if (changed) {
      setEarnedAt(next);
      if (newly.length > 0) {
        supabase
          .from("badge_dates")
          .upsert(
            newly.map((b) => ({
              user_id: userId,
              badge_id: b.id,
              earned_at: next[b.id],
            })),
          )
          .then(({ error }) => {
            if (error) console.warn("Failed to sync badge dates", error);
          });
      }
      if (removed.length > 0) {
        supabase
          .from("badge_dates")
          .delete()
          .eq("user_id", userId)
          .in("badge_id", removed)
          .then(({ error }) => {
            if (error) console.warn("Failed to delete badge dates", error);
          });
      }
    }

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
  }, [hydrated, visitsHydrated, allBadges, earnedAt, userId]);

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
