import { Ionicons } from "@expo/vector-icons";
import { useFocusEffect, useRouter } from "expo-router";
import { useCallback, useMemo, useRef, useState } from "react";
import { Alert, FlatList, Text, View } from "react-native";
import Animated, { FadeIn } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import Glass from "../../components/Glass";
import PressableScale from "../../components/PressableScale";
import MonthCalendar from "../../components/MonthCalendar";
import VisitCard from "../../components/VisitCard";
import { supabase } from "../../lib/supabase";
import {
  dayKey,
  dayKeyToDate,
  formatDayKey,
  getDrinkTotal,
  useVisits,
} from "../../lib/VisitsContext";

export default function HistoryScreen() {
  const { visits, getVisitsForDay, clearVisit, clearHistory, hydrated } =
    useVisits();
  const [selectedDay, setSelectedDay] = useState<string>(dayKey());
  const listRef = useRef<FlatList>(null);
  const router = useRouter();
  const insets = useSafeAreaInsets();

  useFocusEffect(
    useCallback(() => {
      // Opening the tab always starts on today, scrolled to the top.
      setSelectedDay(dayKey());
      listRef.current?.scrollToOffset({ offset: 0, animated: false });
    }, []),
  );

  const confirmClear = () => {
    Alert.alert(
      "Clear all history?",
      "This can't be undone. Choose what to clear:",
      [
        {
          text: "Drink history only",
          style: "destructive",
          onPress: () => clearHistory(false),
        },
        {
          text: "Full reset (incl. visited)",
          style: "destructive",
          onPress: () => clearHistory(true),
        },
        { text: "Cancel", style: "cancel" },
      ],
    );
  };

  const confirmSignOut = () => {
    Alert.alert("Sign out?", "You'll need to sign back in to access your data.", [
      { text: "Cancel", style: "cancel" },
      {
        text: "Sign Out",
        style: "destructive",
        onPress: () => supabase.auth.signOut(),
      },
    ]);
  };

  const markedDays = useMemo(
    () => new Set(visits.map((v) => dayKey(v.date))),
    [visits],
  );

  const dayVisits = getVisitsForDay(selectedDay);
  const dayTotal = dayVisits.reduce((sum, v) => sum + getDrinkTotal(v), 0);
  const isFutureDay =
    dayKeyToDate(selectedDay).getTime() > dayKeyToDate(dayKey()).getTime();

  // Blank over the gradient until data loads, so the calendar/visits don't
  // flash empty before they arrive from Supabase.
  if (!hydrated) return <View className="flex-1" />;

  return (
    <Animated.View entering={FadeIn.duration(350)} className="flex-1">
      <FlatList
        ref={listRef}
        data={dayVisits}
        keyExtractor={(item) => item.id}
        contentContainerStyle={{
          paddingHorizontal: 16,
          paddingTop: insets.top + 8,
          // Clear the floating tab bar pill.
          paddingBottom: insets.bottom + 104,
        }}
        ListHeaderComponent={
          <View className="mb-4">
            <Text className="mb-4 text-3xl font-extrabold text-white">
              History
            </Text>
            <MonthCalendar
              markedDays={markedDays}
              selectedDay={selectedDay}
              onSelectDay={setSelectedDay}
            />
            <Text className="mt-4 text-base font-bold text-white">
              {formatDayKey(selectedDay)}
            </Text>
            {dayVisits.length > 0 ? (
              <Text className="mt-0.5 text-sm text-gray-400">
                {dayVisits.length} {dayVisits.length === 1 ? "bar" : "bars"} •{" "}
                {dayTotal} {dayTotal === 1 ? "drink" : "drinks"}
              </Text>
            ) : null}
            {!isFutureDay ? (
              <PressableScale
                onPress={() => router.push(`/log/${selectedDay}`)}
                className="mt-3 flex-row items-center justify-center rounded-2xl border border-primary/40 bg-primary/15 px-4 py-3"
              >
                <Ionicons name="add-circle-outline" size={18} color="#e0218a" />
                <Text
                  numberOfLines={1}
                  className="ml-2 text-base font-semibold text-primary"
                >
                  Add drinks for this day
                </Text>
              </PressableScale>
            ) : null}
          </View>
        }
        ListEmptyComponent={
          <View className="items-center pt-8">
            <Text className="text-4xl">🍸</Text>
            <Text className="mt-2 text-sm text-gray-400">
              No drinks logged this day.
            </Text>
          </View>
        }
        ListFooterComponent={
          <View className="mt-6">
            {visits.length > 0 ? (
              <PressableScale
                onPress={confirmClear}
                className="mb-3 flex-row items-center justify-center rounded-2xl border border-red-500/40 bg-red-500/15 px-4 py-3"
              >
                <Ionicons name="trash-outline" size={18} color="#ef4444" />
                <Text
                  numberOfLines={1}
                  className="ml-2 text-base font-semibold text-red-500"
                >
                  Clear History
                </Text>
              </PressableScale>
            ) : null}
            <PressableScale onPress={confirmSignOut}>
              <Glass radius={16} bordered className="flex-row items-center justify-center px-4 py-3">
                <Ionicons name="log-out-outline" size={18} color="#9ca3af" />
                <Text className="ml-2 text-base font-semibold text-gray-300">
                  Sign Out
                </Text>
              </Glass>
            </PressableScale>
          </View>
        }
        renderItem={({ item }) => (
          <VisitCard visit={item} onDelete={() => clearVisit(item.id)} />
        )}
      />
    </Animated.View>
  );
}
