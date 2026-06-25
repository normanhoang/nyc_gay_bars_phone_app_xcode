import { Ionicons } from "@expo/vector-icons";
import { useFocusEffect } from "expo-router";
import {
  type ComponentRef,
  useCallback,
  useMemo,
  useRef,
  useState,
} from "react";
import { Modal, Pressable, ScrollView, Text, View } from "react-native";
import Animated, { FadeIn } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import AppBackground from "../../components/AppBackground";
import BadgeTile from "../../components/BadgeTile";
import Glass from "../../components/Glass";
import PressableScale from "../../components/PressableScale";
import ProgressBar from "../../components/ProgressBar";
import { useBadges } from "../../lib/BadgesContext";
import { drinkEmoji } from "../../lib/drinks";
import {
  biggestNight,
  computeVisitedIds,
  distinctBarsVisited,
  favoriteBar,
  longestDayStreak,
  MILESTONE_BADGE_IDS,
  neighborhoodProgress,
  topDrinkType,
  totalDrinkDays,
  totalDrinks,
} from "../../lib/stats";
import { formatDayKey, useVisits } from "../../lib/VisitsContext";

// Sink milestones to the end of a group (earned or unearned) so the
// gold-outlined prestige tiles read as a finale instead of interleaving.
function milestonesLast<T extends { id: string }>(list: T[]): T[] {
  return [
    ...list.filter((b) => !MILESTONE_BADGE_IDS.has(b.id)),
    ...list.filter((b) => MILESTONE_BADGE_IDS.has(b.id)),
  ];
}

function StatCard({
  label,
  value,
  detail,
}: {
  label: string;
  value: string;
  detail?: string;
}) {
  return (
    <View className="mb-3 rounded-3xl bg-white/[0.05] p-4">
      <Text className="text-xs uppercase tracking-wide text-gray-300">
        {label}
      </Text>
      <Text className="mt-1 text-xl font-extrabold text-white">{value}</Text>
      {detail ? (
        <Text className="mt-0.5 text-xs text-gray-400">{detail}</Text>
      ) : null}
    </View>
  );
}

export default function StatsScreen() {
  const { visits, isVisited, hydrated } = useVisits();
  const { badges: badgeList } = useBadges();
  const [showAllBadges, setShowAllBadges] = useState(false);
  const scrollRef = useRef<ComponentRef<typeof Animated.ScrollView>>(null);
  const insets = useSafeAreaInsets();

  // Opening the tab always shows the top of the page.
  useFocusEffect(
    useCallback(() => {
      scrollRef.current?.scrollTo({ y: 0, animated: false });
    }, []),
  );

  const visitedIds = useMemo(
    () => computeVisitedIds(isVisited),
    [isVisited],
  );

  const drinks = totalDrinks(visits);
  const drinkDays = totalDrinkDays(visits);
  const streak = longestDayStreak(visits);
  const bars = distinctBarsVisited(visits);
  const favorite = favoriteBar(visits);
  const topDrink = topDrinkType(visits);
  const biggest = biggestNight(visits);
  const progress = useMemo(
    () => neighborhoodProgress(visitedIds),
    [visitedIds],
  );

  // Earned badges, most recently earned first (ties keep definition order).
  const earnedBadges = useMemo(
    () =>
      badgeList
        .filter((b) => b.earned)
        .sort((a, b) => (b.earnedAt ?? "").localeCompare(a.earnedAt ?? "")),
    [badgeList],
  );
  const recentBadges = earnedBadges.slice(0, 4);
  const unearnedBadges = useMemo(
    () => badgeList.filter((b) => !b.earned),
    [badgeList],
  );
  // All-badges modal order: earned then unearned, milestones last within each.
  const earnedOrdered = useMemo(
    () => milestonesLast(earnedBadges),
    [earnedBadges],
  );
  const unearnedOrdered = useMemo(
    () => milestonesLast(unearnedBadges),
    [unearnedBadges],
  );

  // Blank over the gradient until data loads, so the empty state doesn't
  // flash before the user's visits arrive from AsyncStorage.
  if (!hydrated) return <View className="flex-1" />;

  if (visits.length === 0 && visitedIds.size === 0) {
    return (
      <Animated.View
        entering={FadeIn.duration(350)}
        className="flex-1 items-center justify-center px-8"
      >
        <Text className="text-4xl">📊</Text>
        <Text className="mt-3 text-center text-base text-gray-400">
          Log your first drink to start earning stats and badges.
        </Text>
      </Animated.View>
    );
  }

  return (
    <Animated.ScrollView
      entering={FadeIn.duration(350)}
      ref={scrollRef}
      className="flex-1"
      contentContainerStyle={{
        paddingHorizontal: 16,
        paddingTop: insets.top + 8,
        // Clear the floating tab bar pill.
        paddingBottom: insets.bottom + 104,
      }}
    >
      <Text className="mb-4 text-3xl font-extrabold text-white">Stats</Text>
      <View className="mb-3">
        <Text className="mb-2 text-xs uppercase tracking-wide text-gray-300">
          Totals
        </Text>
        <View className="flex-row">
          <View className="mr-3 flex-1 items-center rounded-3xl border border-primary/30 bg-primary/15 px-2 py-4">
            <Text className="text-2xl font-extrabold text-primary">
              {drinks}
            </Text>
            <Text className="mt-1 text-xs text-gray-400">drinks</Text>
          </View>
          <View className="mr-3 flex-1 items-center rounded-3xl border border-primary/30 bg-primary/15 px-2 py-4">
            <Text className="text-2xl font-extrabold text-primary">
              {drinkDays}
            </Text>
            <Text className="mt-1 text-xs text-gray-400">drink-days</Text>
          </View>
          <View className="flex-1 items-center rounded-3xl border border-primary/30 bg-primary/15 px-2 py-4">
            <Text className="text-2xl font-extrabold text-primary">{bars}</Text>
            <Text className="mt-1 text-xs text-gray-400">bars</Text>
          </View>
        </View>
      </View>

      {favorite ? (
        <StatCard
          label="Favorite bar"
          value={favorite.name}
          detail={favorite.neighborhood}
        />
      ) : null}
      {topDrink ? (
        <StatCard
          label="Top drink"
          value={`${drinkEmoji(topDrink.type)} ${topDrink.type}`}
          detail={`${topDrink.count} logged all-time`}
        />
      ) : null}
      {biggest ? (
        <StatCard
          label="Biggest night"
          value={`${biggest.total} ${biggest.total === 1 ? "drink" : "drinks"}`}
          detail={formatDayKey(biggest.day)}
        />
      ) : null}
      {streak > 0 ? (
        <StatCard
          label="Longest streak"
          value={`${streak} ${streak === 1 ? "day" : "days"}`}
          detail="Most consecutive days with drinks logged"
        />
      ) : null}

      <Text className="mb-2 mt-3 text-base font-bold text-white">
        Neighborhoods
      </Text>
      <View className="rounded-3xl bg-white/[0.05] px-4 py-3">
        {progress.map((p, i) => {
          const complete = p.visited === p.total;
          return (
            <View key={p.neighborhood} className="py-2">
              <View className="mb-1.5 flex-row items-center justify-between">
                <Text className="flex-1 pr-3 text-sm text-white">
                  {p.neighborhood}
                  {complete ? " 👑" : ""}
                </Text>
                <Text
                  className={
                    complete
                      ? "text-xs font-bold text-primary"
                      : "text-xs font-semibold text-gray-400"
                  }
                >
                  {p.visited} / {p.total}
                </Text>
              </View>
              <ProgressBar progress={p.visited / p.total} delay={i * 60} />
            </View>
          );
        })}
      </View>

      <View className="mb-2 mt-5 flex-row items-center justify-between">
        <Text className="text-base font-bold text-white">Recent badges</Text>
        <PressableScale
          onPress={() => setShowAllBadges(true)}
          hitSlop={8}
          className="flex-row items-center"
        >
          <Text
            numberOfLines={1}
            className="text-sm font-semibold text-primary"
          >
            All badges ({earnedBadges.length}/{badgeList.length})
          </Text>
          <Ionicons name="chevron-forward" size={14} color="#e0218a" />
        </PressableScale>
      </View>
      {recentBadges.length > 0 ? (
        <View className="flex-row flex-wrap justify-between">
          {recentBadges.map((b) => (
            <BadgeTile key={b.id} badge={b} />
          ))}
        </View>
      ) : (
        <View className="items-center rounded-3xl bg-white/[0.05] p-4">
          <Text className="text-sm text-gray-300">
            No badges yet — log a drink to start earning.
          </Text>
        </View>
      )}

      <Modal
        visible={showAllBadges}
        animationType="slide"
        presentationStyle="pageSheet"
        onRequestClose={() => setShowAllBadges(false)}
      >
        <View className="flex-1 bg-ink">
          <AppBackground />
          <View className="flex-row items-center justify-between px-4 pb-3 pt-5">
            <Text className="text-lg font-extrabold text-white">
              Badges · {earnedBadges.length}/{badgeList.length} earned
            </Text>
            <Pressable
              onPress={() => setShowAllBadges(false)}
              hitSlop={12}
              accessibilityRole="button"
              accessibilityLabel="Close"
            >
              <Glass radius={18} className="h-9 w-9 items-center justify-center">
                <Ionicons name="close" size={20} color="#ffffff" />
              </Glass>
            </Pressable>
          </View>
          <ScrollView contentContainerStyle={{ padding: 16, paddingBottom: 40 }}>
            <View className="flex-row flex-wrap justify-between">
              {earnedOrdered.map((b) => (
                <BadgeTile key={b.id} badge={b} showDate />
              ))}
              {unearnedOrdered.map((b) => (
                <BadgeTile key={b.id} badge={b} />
              ))}
            </View>
          </ScrollView>
        </View>
      </Modal>
    </Animated.ScrollView>
  );
}
