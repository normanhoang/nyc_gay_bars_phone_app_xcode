import { Pressable, ScrollView, Text, View } from "react-native";
import { NEIGHBORHOOD_POLYGONS } from "../lib/neighborhoods";
import type { Bar } from "../lib/types";

type Props = {
  bars: Bar[];
  showOutlines: boolean;
  onSelectBar: (barId: string) => void;
  onSelectNeighborhood: (name: string) => void;
  visitedIds: Set<string>;
  /** Accepted for parity with the native map; no zoom on the web stand-in. */
  onZoomOut?: () => boolean | void;
  frameNonce?: number;
};

/**
 * Web fallback for BarMap. `react-native-maps` has no web implementation, so on
 * web we render a simple interactive list standing in for the map: neighborhood
 * chips in outline mode, bar rows in pin mode. Metro resolves this `.web.tsx`
 * over BarMap.tsx automatically for the web platform, keeping the native map
 * (and its native-only dependency) out of the web bundle.
 */
export default function BarMap({
  bars,
  showOutlines,
  onSelectBar,
  onSelectNeighborhood,
  visitedIds,
}: Props) {
  return (
    <View className="flex-1 bg-ink-soft">
      <View className="items-center px-6 pt-6">
        <Text className="text-center text-xs text-gray-400">
          🗺️ The interactive map runs on iOS/Android (Expo Go). This is a web
          stand-in.
        </Text>
      </View>

      <ScrollView contentContainerStyle={{ padding: 16 }}>
        {showOutlines
          ? Object.keys(NEIGHBORHOOD_POLYGONS).map((name) => (
              <Pressable
                key={name}
                onPress={() => onSelectNeighborhood(name)}
                className="mb-2 rounded-2xl border border-primary/40 bg-primary/15 px-4 py-3 active:opacity-70"
              >
                <Text className="text-base font-semibold text-white">
                  {name}
                </Text>
              </Pressable>
            ))
          : bars.map((bar) => (
              <Pressable
                key={bar.id}
                onPress={() => onSelectBar(bar.id)}
                className={
                  visitedIds.has(bar.id)
                    ? "mb-2 rounded-2xl border border-primary/40 bg-primary/15 px-4 py-3 active:opacity-70"
                    : "mb-2 rounded-2xl bg-ink-card px-4 py-3 active:opacity-70"
                }
              >
                <Text className="text-base font-semibold text-white">
                  {bar.name}
                </Text>
                <Text className="mt-0.5 text-xs text-gray-400">
                  {bar.neighborhood} • {bar.address}
                </Text>
              </Pressable>
            ))}
      </ScrollView>
    </View>
  );
}
