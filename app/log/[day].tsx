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
import Glass from "../../components/Glass";
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
  const [pickedBarId, setPickedBarId] = useState<string | null>(null);

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
