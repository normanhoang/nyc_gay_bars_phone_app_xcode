import { Ionicons } from "@expo/vector-icons";
import { useLocalSearchParams, useRouter } from "expo-router";
import { useMemo, useState } from "react";
import {
  FlatList,
  Keyboard,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import Animated, { SlideInDown } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import AppBackground from "../../components/AppBackground";
import BarDetailSheet from "../../components/BarDetailSheet";
import BarListItem from "../../components/BarListItem";
import FilterChips from "../../components/FilterChips";
import Glass from "../../components/Glass";
import { BARS, NEIGHBORHOODS } from "../../lib/bars";
import { distanceMiles, neighborhoodsByProximity } from "../../lib/geo";
import { useDeviceCoords } from "../../lib/useDeviceCoords";
import {
  dayKey,
  formatDayKey,
  getDrinkTotal,
  useVisits,
} from "../../lib/VisitsContext";

type SortMode = "name" | "nearest";

const ALL = "All";

export default function LogDayScreen() {
  const { day } = useLocalSearchParams<{ day: string }>();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { getVisitFor, isVisited } = useVisits();
  const [query, setQuery] = useState("");
  const [sort, setSort] = useState<SortMode>("name");
  const [neighborhood, setNeighborhood] = useState<string>(ALL);
  const [pickedBarId, setPickedBarId] = useState<string | null>(null);
  const coords = useDeviceCoords();

  const targetDay = day ?? dayKey();

  // Order neighborhood chips by proximity once we have a location; All stays
  // pinned leftmost. Falls back to the alphabetical default without location.
  const neighborhoodOptions = useMemo(
    () =>
      coords
        ? neighborhoodsByProximity(coords.lat, coords.lng)
        : NEIGHBORHOODS,
    [coords],
  );

  // Miles from the device to each bar, or null without a location.
  const distances = useMemo(
    () =>
      coords
        ? new Map(
            BARS.map((b) => [b.id, distanceMiles(coords.lat, coords.lng, b)]),
          )
        : null,
    [coords],
  );

  const filteredBars = useMemo(() => {
    const q = query.trim().toLowerCase();
    return BARS.filter((b) => {
      if (neighborhood !== ALL && b.neighborhood !== neighborhood) return false;
      if (
        q &&
        !`${b.name} ${b.neighborhood} ${b.address} ${b.tags?.join(" ") ?? ""}`
          .toLowerCase()
          .includes(q)
      ) {
        return false;
      }
      return true;
    }).sort((a, b) =>
      sort === "nearest" && distances
        ? (distances.get(a.id) ?? Infinity) - (distances.get(b.id) ?? Infinity)
        : a.name.localeCompare(b.name),
    );
  }, [neighborhood, query, sort, distances]);

  const selectNeighborhood = (value: string) => {
    // Chips capture their own taps, so the keyboard would otherwise stay up.
    Keyboard.dismiss();
    setNeighborhood(value);
    // Picking a neighborhood starts a fresh browse — drop any search query.
    setQuery("");
  };

  // Picking a bar doesn't navigate — the logger slides in over the picker
  // inside this same modal. One modal means swiping down (or the X) always
  // lands straight on History, with no stale picker left in the stack.
  const pickBar = (id: string) => {
    Keyboard.dismiss();
    setPickedBarId(id);
  };

  return (
    <View className="flex-1 bg-ink">
      <AppBackground />
      <View className="flex-row items-center justify-between px-4 pb-1 pt-4">
        <Text className="text-lg font-extrabold text-white">Pick a bar</Text>
        <Pressable
          onPress={() => router.back()}
          hitSlop={12}
          accessibilityRole="button"
          accessibilityLabel="Close"
          className="active:opacity-60"
        >
          <Glass radius={18} className="h-9 w-9 items-center justify-center">
            <Ionicons name="close" size={20} color="#ffffff" />
          </Glass>
        </Pressable>
      </View>
      <View className="px-4 pb-3 pt-2">
        <Text className="mb-3 text-sm text-gray-400">
          Logging drinks for {formatDayKey(targetDay)} — which bar were you at?
        </Text>
        <Glass radius={16} bordered className="flex-row items-center px-3">
          <Ionicons name="search" size={18} color="#9ca3af" />
          <TextInput
            value={query}
            onChangeText={setQuery}
            placeholder="Search bars, neighborhoods, addresses…"
            placeholderTextColor="#6b7280"
            autoCorrect={false}
            returnKeyType="search"
            className="flex-1 px-2 py-3 text-base text-white"
          />
          {query.length > 0 ? (
            <Pressable
              onPress={() => setQuery("")}
              hitSlop={8}
              accessibilityRole="button"
              accessibilityLabel="Clear search"
            >
              <Ionicons name="close-circle" size={18} color="#9ca3af" />
            </Pressable>
          ) : null}
        </Glass>
      </View>

      <View className="pb-3 pl-4">
        <FilterChips
          options={[ALL, ...neighborhoodOptions]}
          value={neighborhood}
          onChange={selectNeighborhood}
        />
      </View>

      {distances ? (
        <View className="mb-2 flex-row items-center justify-end px-4">
          <Pressable
            onPress={() => {
              Keyboard.dismiss();
              setSort("name");
            }}
            hitSlop={6}
          >
            <Text
              className={
                sort === "name"
                  ? "text-xs font-bold text-primary"
                  : "text-xs font-semibold text-gray-500"
              }
            >
              A–Z
            </Text>
          </Pressable>
          <Text className="text-xs text-gray-600"> · </Text>
          <Pressable
            onPress={() => {
              Keyboard.dismiss();
              setSort("nearest");
            }}
            hitSlop={6}
          >
            <Text
              className={
                sort === "nearest"
                  ? "text-xs font-bold text-primary"
                  : "text-xs font-semibold text-gray-500"
              }
            >
              Nearest
            </Text>
          </Pressable>
        </View>
      ) : null}

      <FlatList
        data={filteredBars}
        keyExtractor={(item) => item.id}
        keyboardShouldPersistTaps="handled"
        contentContainerStyle={{
          paddingHorizontal: 16,
          paddingBottom: insets.bottom + 16,
          flexGrow: 1,
        }}
        ListEmptyComponent={
          <View className="items-center pt-16">
            <Text className="text-4xl">🔍</Text>
            <Text className="mt-2 text-base text-gray-400">
              No bars match your search.
            </Text>
          </View>
        }
        renderItem={({ item }) => {
          const visit = getVisitFor(item.id, targetDay);
          return (
            <BarListItem
              bar={item}
              todayCount={visit ? getDrinkTotal(visit) : 0}
              visited={isVisited(item.id)}
              distanceMi={distances?.get(item.id)}
              onPress={() => pickBar(item.id)}
            />
          );
        }}
      />

      {pickedBarId ? (
        <Animated.View
          entering={SlideInDown.duration(320)}
          style={StyleSheet.absoluteFill}
        >
          <BarDetailSheet
            barId={pickedBarId}
            day={targetDay}
            onClose={() => router.back()}
          />
        </Animated.View>
      ) : null}
    </View>
  );
}
