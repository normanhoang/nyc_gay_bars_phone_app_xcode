import { Ionicons } from "@expo/vector-icons";
import { useFocusEffect, useRouter } from "expo-router";
import { useCallback, useMemo, useState } from "react";
import {
  FlatList,
  InputAccessoryView,
  Keyboard,
  Platform,
  Pressable,
  Text,
  TextInput,
  View,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import BarListItem from "../../components/BarListItem";
import BarMap from "../../components/BarMap";
import FilterChips from "../../components/FilterChips";
import Glass from "../../components/Glass";
import SegmentedToggle from "../../components/SegmentedToggle";
import { useSetTabSwipeEnabled } from "../../components/TabSwipeContext";
import { BARS, NEIGHBORHOODS } from "../../lib/bars";
import { distanceMiles, neighborhoodsByProximity } from "../../lib/geo";
import { computeVisitedIds } from "../../lib/stats";
import { useDeviceCoords } from "../../lib/useDeviceCoords";
import { getDrinkTotal, useVisits } from "../../lib/VisitsContext";

type ViewMode = "map" | "list";
type SortMode = "name" | "nearest";

const ALL = "All";

function visitMessage(visited: number, total: number, isAll: boolean): string {
  if (total === 0) return "";
  if (visited === 0) return "Never been — time to explore!";
  if (visited === total) {
    return isAll
      ? "You've conquered the scene! 👑"
      : "You've conquered the neighborhood! 👑";
  }
  const pct = visited / total;
  if (pct <= 0.25) return "Just getting started...";
  if (pct <= 0.5) return "Making the rounds!";
  if (pct <= 0.75) return "A regular on the scene!";
  return "Almost a legend!";
}

export default function ExploreScreen() {
  const [mode, setMode] = useState<ViewMode>("map");
  const [sort, setSort] = useState<SortMode>("name");
  const [neighborhood, setNeighborhood] = useState<string>(ALL);
  const [query, setQuery] = useState("");
  // Bumped when the selected chip is re-pressed so the map re-centers on it
  // (a zoom-out gesture switches the filter without moving the camera).
  const [frameNonce, setFrameNonce] = useState(0);
  // Used for distances, the Nearest sort, and proximity-ordered chips. The
  // filter always starts on "All".
  const coords = useDeviceCoords();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { getVisitFor, isVisited } = useVisits();
  const setTabSwipeEnabled = useSetTabSwipeEnabled();

  // Disable tab paging while the map is showing so the pager doesn't steal the
  // map's horizontal pan; re-enable on list view and whenever Explore blurs.
  useFocusEffect(
    useCallback(() => {
      setTabSwipeEnabled(mode === "list");
      return () => setTabSwipeEnabled(true);
    }, [mode, setTabSwipeEnabled]),
  );

  const openBar = (id: string) => router.push(`/bar/${id}`);

  const selectNeighborhood = (value: string) => {
    // Chips capture their own taps, so the screen-level dismiss never fires.
    Keyboard.dismiss();
    if (value === neighborhood) {
      // Re-pressing the selected chip re-centers the map on it.
      setFrameNonce((n) => n + 1);
    }
    setNeighborhood(value);
    // Picking a neighborhood starts a fresh browse — drop any search query.
    setQuery("");
  };

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

  // Bars the user has ever visited (for the map pin + list indicators).
  const visitedIds = useMemo(() => computeVisitedIds(isVisited), [isVisited]);

  // Order neighborhood chips by proximity once we have a location; All stays
  // pinned leftmost. Falls back to the alphabetical default without location.
  const neighborhoodOptions = useMemo(
    () =>
      coords
        ? neighborhoodsByProximity(coords.lat, coords.lng)
        : NEIGHBORHOODS,
    [coords],
  );

  // All bars in the selected neighborhood (ignoring search query) — used for
  // the visited-count stat below the chips.
  const neighborhoodBars = useMemo(
    () => (neighborhood === ALL ? BARS : BARS.filter((b) => b.neighborhood === neighborhood)),
    [neighborhood],
  );
  const visitedCount = useMemo(
    () => neighborhoodBars.filter((b) => visitedIds.has(b.id)).length,
    [neighborhoodBars, visitedIds],
  );

  return (
    <Pressable className="flex-1" onPress={Keyboard.dismiss}>
      <View className="px-4 pb-3" style={{ paddingTop: insets.top + 8 }}>
        <Text className="mb-3 text-3xl font-extrabold text-white">
          NYC Gay Bars
        </Text>

        <Glass radius={16} bordered className="mb-3 flex-row items-center px-3">
          <Ionicons name="search" size={18} color="#9ca3af" />
          <TextInput
            value={query}
            onChangeText={setQuery}
            // Searching is a list activity — focusing the field switches the
            // view; dismissing the keyboard intentionally leaves it alone.
            onFocus={() => setMode("list")}
            placeholder="Search bars, neighborhoods, addresses…"
            placeholderTextColor="#6b7280"
            autoCorrect={false}
            returnKeyType="search"
            inputAccessoryViewID={
              Platform.OS === "ios" ? "search-dismiss" : undefined
            }
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

        <SegmentedToggle<ViewMode>
          options={[
            { value: "map", label: "Map" },
            { value: "list", label: "List" },
          ]}
          value={mode}
          onChange={(value) => {
            Keyboard.dismiss();
            setMode(value);
          }}
        />
      </View>

      <View className="pb-1 pl-4">
        <FilterChips
          options={[ALL, ...neighborhoodOptions]}
          value={neighborhood}
          onChange={selectNeighborhood}
        />
      </View>

      <View
        className={
          mode === "list" && distances
            ? "mb-2 flex-row items-center justify-between px-4"
            : "mb-2 flex-row items-center justify-center px-4"
        }
      >
        <View className="flex-row items-center">
          <Text className="text-xs font-semibold text-primary">
            {visitedCount} / {neighborhoodBars.length}
          </Text>
          <Text className="text-xs text-gray-500"> visited · </Text>
          <Text className="text-xs text-gray-400">
            {visitMessage(
              visitedCount,
              neighborhoodBars.length,
              neighborhood === ALL,
            )}
          </Text>
        </View>
        {mode === "list" && distances ? (
          <View className="flex-row items-center">
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
      </View>

      {mode === "list" ? (
        <FlatList
          data={filteredBars}
          keyExtractor={(item) => item.id}
          keyboardShouldPersistTaps="handled"
          keyboardDismissMode="on-drag"
          contentContainerStyle={{
            paddingHorizontal: 16,
            // Clear the floating tab bar pill so the last row scrolls above it.
            paddingBottom: insets.bottom + 104,
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
            const visit = getVisitFor(item.id);
            return (
              <BarListItem
                bar={item}
                todayCount={visit ? getDrinkTotal(visit) : 0}
                visited={visitedIds.has(item.id)}
                distanceMi={distances?.get(item.id)}
                onPress={() => openBar(item.id)}
              />
            );
          }}
        />
      ) : (
        <View className="flex-1 overflow-hidden">
          <BarMap
            bars={filteredBars}
            showOutlines={neighborhood === ALL && query.trim() === ""}
            onSelectBar={openBar}
            onSelectNeighborhood={selectNeighborhood}
            visitedIds={visitedIds}
            frameNonce={frameNonce}
            onZoomOut={() => {
              if (neighborhood === ALL) return false;
              setNeighborhood(ALL);
              return true;
            }}
          />
        </View>
      )}

      {Platform.OS === "ios" ? (
        // iOS keyboards have no built-in dismiss key — give the search field
        // an accessory bar with a Done button instead.
        <InputAccessoryView nativeID="search-dismiss" backgroundColor="#16161f">
          <View className="flex-row justify-end px-4 py-2">
            <Pressable onPress={Keyboard.dismiss} hitSlop={8}>
              <Text className="text-base font-semibold text-primary">Done</Text>
            </Pressable>
          </View>
        </InputAccessoryView>
      ) : null}
    </Pressable>
  );
}
