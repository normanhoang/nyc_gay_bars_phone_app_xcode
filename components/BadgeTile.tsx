import { LinearGradient } from "expo-linear-gradient";
import { StyleSheet, Text, View } from "react-native";
import type { BadgeWithDate } from "../lib/BadgesContext";
import { MILESTONE_BADGE_IDS } from "../lib/stats";

type Props = {
  badge: BadgeWithDate;
  /** Show the earned date under the description (all-badges popup). */
  showDate?: boolean;
};

function formatEarnedAt(iso: string): string {
  return new Date(iso).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

/**
 * A badge tile — an award medallion on a soft gradient wash, deliberately
 * not a Glass surface or bordered (those read as buttons). Earned tiles get
 * a magenta→violet glow; unearned ones stay muted with dimmed content.
 * Prestige milestones ([[MILESTONE_BADGE_IDS]]) carry a gold outline (dimmer
 * while still locked) to mark them as the special ones to chase.
 */
export default function BadgeTile({ badge, showDate = false }: Props) {
  const milestone = MILESTONE_BADGE_IDS.has(badge.id);
  return (
    <View
      className={
        milestone
          ? badge.earned
            ? "mb-3 min-h-[160px] w-[48%] items-center justify-center overflow-hidden rounded-3xl border border-[#e3b34180] px-3 py-5"
            : "mb-3 min-h-[160px] w-[48%] items-center justify-center overflow-hidden rounded-3xl border border-[#e3b34140] bg-white/[0.04] px-3 py-5"
          : badge.earned
            ? "mb-3 min-h-[160px] w-[48%] items-center justify-center overflow-hidden rounded-3xl px-3 py-5"
            : "mb-3 min-h-[160px] w-[48%] items-center justify-center overflow-hidden rounded-3xl bg-white/[0.04] px-3 py-5"
      }
    >
      {badge.earned ? (
        <LinearGradient
          colors={["rgba(224,33,138,0.35)", "rgba(110,60,190,0.22)"]}
          start={{ x: 0, y: 0 }}
          end={{ x: 1, y: 1 }}
          pointerEvents="none"
          style={StyleSheet.absoluteFill}
        />
      ) : null}
      <View
        className={badge.earned ? "items-center" : "items-center opacity-40"}
      >
        <Text className="text-4xl">{badge.emoji}</Text>
        <Text className="mt-3 text-center text-sm font-bold text-white">
          {badge.title}
        </Text>
        <Text className="mt-1 text-center text-xs leading-4 text-gray-400">
          {badge.description}
        </Text>
        {showDate && badge.earned && badge.earnedAt ? (
          <Text className="mt-2 text-center text-[10px] font-semibold text-primary">
            Earned {formatEarnedAt(badge.earnedAt)}
          </Text>
        ) : null}
      </View>
    </View>
  );
}
