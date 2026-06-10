import { Ionicons } from "@expo/vector-icons";
import { Stack, useLocalSearchParams, useRouter } from "expo-router";
import { useMemo, useState } from "react";
import { FlatList, Pressable, Text, TextInput, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import BarListItem from "../../components/BarListItem";
import { BARS } from "../../lib/bars";
import {
  dayKey,
  formatDayKey,
  getDrinkTotal,
  useVisits,
} from "../../lib/VisitsContext";

export default function LogDayScreen() {
  const { day } = useLocalSearchParams<{ day: string }>();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { getVisitFor, isVisited } = useVisits();
  const [query, setQuery] = useState("");

  const targetDay = day ?? dayKey();

  const filteredBars = useMemo(() => {
    const q = query.trim().toLowerCase();
    return BARS.filter(
      (b) =>
        !q ||
        `${b.name} ${b.neighborhood} ${b.address} ${b.tags?.join(" ") ?? ""}`
          .toLowerCase()
          .includes(q),
    ).sort((a, b) => a.name.localeCompare(b.name));
  }, [query]);

  // Swap the picker for the drink logger so closing it returns to History.
  const pickBar = (id: string) => router.replace(`/bar/${id}?day=${targetDay}`);

  return (
    <View className="flex-1 bg-ink">
      <Stack.Screen options={{ title: "Pick a bar" }} />
      <View className="px-4 pb-3 pt-4">
        <Text className="mb-3 text-sm text-gray-400">
          Logging drinks for {formatDayKey(targetDay)} — which bar were you at?
        </Text>
        <View className="flex-row items-center rounded-2xl bg-ink-card px-3">
          <Ionicons name="search" size={18} color="#6b7280" />
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
              <Ionicons name="close-circle" size={18} color="#6b7280" />
            </Pressable>
          ) : null}
        </View>
      </View>

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
              onPress={() => pickBar(item.id)}
            />
          );
        }}
      />
    </View>
  );
}
