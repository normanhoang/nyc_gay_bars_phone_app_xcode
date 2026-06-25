import { Ionicons } from "@expo/vector-icons";
import { Text, View } from "react-native";
import Glass from "./Glass";
import PressableScale from "./PressableScale";
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
    <PressableScale onPress={onPress} className="mb-3">
      <Glass
        radius={24}
        bordered={visited}
        borderColor="rgba(224,33,138,0.5)"
        className="flex-row items-center p-4"
      >
        {visited ? (
          // Magenta wash to flag a visited bar without an opacity utility
          // (which would break native glass).
          <View
            pointerEvents="none"
            className="absolute inset-0 bg-primary/20"
          />
        ) : null}
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
                className="mr-1.5 rounded-full border border-white/10 bg-white/[0.08] px-2 py-0.5"
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
          <View className="mr-1 flex-row items-center rounded-full bg-primary/25 px-2.5 py-1">
            <Text className="mr-1 text-sm">🍹</Text>
            <Text className="text-sm font-bold text-primary">{todayCount}</Text>
          </View>
        ) : null}

        <Ionicons name="chevron-forward" size={18} color="#9ca3af" />
      </Glass>
    </PressableScale>
  );
}
