import { Ionicons } from "@expo/vector-icons";
import { Pressable, Text, View } from "react-native";
import type { Bar } from "../lib/types";

type Props = {
  bar: Bar;
  /** Count of drinks logged at this bar today (0 = none). */
  todayCount: number;
  /** Whether the user has ever visited this bar. */
  visited: boolean;
  /** Miles from the user's location; omitted when location is unavailable. */
  distanceMi?: number;
  onPress: () => void;
};

function formatMiles(mi: number): string {
  return mi >= 10 ? `${Math.round(mi)} mi` : `${mi.toFixed(1)} mi`;
}

export default function BarListItem({
  bar,
  todayCount,
  visited,
  distanceMi,
  onPress,
}: Props) {
  return (
    <Pressable
      onPress={onPress}
      className={
        visited
          ? "mb-3 flex-row items-center rounded-2xl border border-primary/40 bg-primary/15 p-4 active:opacity-80"
          : "mb-3 flex-row items-center rounded-2xl border border-transparent bg-ink-card p-4 active:opacity-80"
      }
    >
      <View className="flex-1 pr-3">
        <Text className="text-base font-semibold text-white">{bar.name}</Text>
        <Text className="mt-0.5 text-xs font-medium text-primary">
          {bar.neighborhood}
          {distanceMi !== undefined ? (
            <Text className="font-normal text-gray-400">
              {"  ·  "}
              {formatMiles(distanceMi)}
            </Text>
          ) : null}
        </Text>
        <Text className="mt-1 text-xs text-gray-400" numberOfLines={1}>
          {bar.address}
        </Text>
        {bar.tags?.length ? (
          <View className="mt-1.5 flex-row">
            {bar.tags.slice(0, 3).map((tag) => (
              <View
                key={tag}
                className="mr-1.5 rounded-full bg-ink-soft px-2 py-0.5"
              >
                <Text className="text-[10px] font-medium text-gray-400">
                  {tag}
                </Text>
              </View>
            ))}
          </View>
        ) : null}
      </View>

      {todayCount > 0 ? (
        <View className="mr-1 flex-row items-center rounded-full bg-primary/20 px-2.5 py-1">
          <Text className="mr-1 text-sm">🍹</Text>
          <Text className="text-sm font-bold text-primary">{todayCount}</Text>
        </View>
      ) : null}

      <Ionicons name="chevron-forward" size={18} color="#6b7280" />
    </Pressable>
  );
}
