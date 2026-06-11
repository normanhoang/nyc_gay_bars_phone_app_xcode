import { Text, View } from "react-native";
import type { BadgeWithDate } from "../lib/BadgesContext";
import Glass from "./Glass";

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

export default function BadgeTile({ badge, showDate = false }: Props) {
  return (
    <Glass
      className={
        badge.earned
          ? "mb-3 w-[48%] items-center rounded-3xl border border-primary/40 p-4"
          : "mb-3 w-[48%] items-center rounded-3xl p-4"
      }
    >
      {/* Dim unearned tiles with an overlay rather than an opacity utility,
          which would error on native Liquid Glass. */}
      {!badge.earned ? (
        <View pointerEvents="none" className="absolute inset-0 bg-black/40" />
      ) : null}
      <Text className="text-3xl">{badge.emoji}</Text>
      <Text
        className={
          badge.earned
            ? "mt-2 text-center text-sm font-semibold text-white"
            : "mt-2 text-center text-sm font-semibold text-gray-400"
        }
      >
        {badge.title}
      </Text>
      <Text className="mt-1 text-center text-xs text-gray-400">
        {badge.description}
      </Text>
      {showDate && badge.earned && badge.earnedAt ? (
        <Text className="mt-1 text-center text-[10px] font-semibold text-primary">
          Earned {formatEarnedAt(badge.earnedAt)}
        </Text>
      ) : null}
    </Glass>
  );
}
