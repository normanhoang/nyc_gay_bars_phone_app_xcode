import { Ionicons } from "@expo/vector-icons";
import { useEffect, useRef, useState } from "react";
import {
  Alert,
  Linking,
  Pressable,
  ScrollView,
  Text,
  TextInput,
  View,
} from "react-native";
import { getBarById } from "../lib/bars";
import {
  dayKey,
  formatDayKey,
  getDrinkTotal,
  useVisits,
} from "../lib/VisitsContext";
import AppBackground from "./AppBackground";
import BadgeToast from "./BadgeToast";
import CountUp from "./CountUp";
import DrinkLogger from "./DrinkLogger";
import Glass from "./Glass";

function NotesSection({
  note,
  editable,
  onCommit,
}: {
  note: string | undefined;
  /** False until a drink has been logged for the day (notes need a visit). */
  editable: boolean;
  onCommit: (note: string) => void;
}) {
  const [draft, setDraft] = useState(note ?? "");
  // Commit on unmount too — the modal can be swiped away without blurring.
  const latest = useRef({ draft, editable, onCommit });
  latest.current = { draft, editable, onCommit };
  useEffect(
    () => () => {
      const { draft, editable, onCommit } = latest.current;
      if (editable) onCommit(draft);
    },
    [],
  );

  return (
    <View className="mt-5">
      <Text className="mb-3 text-base font-bold text-white">Notes</Text>
      {editable ? (
        <TextInput
          value={draft}
          onChangeText={setDraft}
          onEndEditing={() => onCommit(draft)}
          onBlur={() => onCommit(draft)}
          placeholder="How was the night?…"
          placeholderTextColor="#6b7280"
          multiline
          className="min-h-[80px] rounded-2xl border border-white/10 bg-white/[0.06] px-4 py-3 text-base text-white"
        />
      ) : (
        <View className="rounded-2xl border border-white/10 bg-white/[0.04] px-4 py-3">
          <Text className="text-sm text-gray-500">
            Log a drink to add a note about this visit.
          </Text>
        </View>
      )}
    </View>
  );
}

type Props = {
  barId: string;
  /** Log against this past day instead of today. */
  day?: string;
  onClose: () => void;
};

/**
 * The full bar-logging UI. Rendered two ways: as the body of the bar/[id]
 * modal (opened from Explore, logs today) and in-place inside the log/[day]
 * picker modal (backdated flow) — a single modal there means swiping down
 * lands straight on History, with no stacked picker left underneath.
 */
export default function BarDetailSheet({ barId, day, onClose }: Props) {
  const bar = getBarById(barId);
  const targetDay = day ?? dayKey();
  const isTargetToday = targetDay === dayKey();
  const {
    getVisitFor,
    logDrink,
    removeDrink,
    setVisitNote,
    isVisited,
    setVisited,
    getVisitsForBar,
  } = useVisits();

  if (!bar) {
    return (
      <View className="flex-1 bg-ink">
        <AppBackground />
        <View className="flex-row justify-end px-4 pt-4">
          <Pressable
            onPress={onClose}
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
        <View className="flex-1 items-center justify-center px-8">
          <Text className="text-base text-white">Bar not found.</Text>
        </View>
      </View>
    );
  }

  const visit = getVisitFor(bar.id, targetDay);
  const total = visit ? getDrinkTotal(visit) : 0;
  const visited = isVisited(bar.id);

  const openDirections = () => {
    const { latitude: lat, longitude: lng, name } = bar;
    const apple = `https://maps.apple.com/?daddr=${lat},${lng}&q=${encodeURIComponent(
      name,
    )}`;
    const google = `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`;
    Alert.alert("Get directions", `Open directions to ${name} in:`, [
      { text: "Apple Maps", onPress: () => Linking.openURL(apple) },
      { text: "Google Maps", onPress: () => Linking.openURL(google) },
      { text: "Cancel", style: "cancel" },
    ]);
  };

  const toggleVisited = () => {
    if (!visited) {
      setVisited(bar.id, true, targetDay);
      return;
    }
    const drinkDays = getVisitsForBar(bar.id).length;
    if (drinkDays > 0) {
      Alert.alert(
        "Mark as never visited?",
        `This will remove ${drinkDays} logged drink-day${
          drinkDays === 1 ? "" : "s"
        } for ${bar.name}.`,
        [
          { text: "Cancel", style: "cancel" },
          {
            text: "Remove",
            style: "destructive",
            onPress: () => setVisited(bar.id, false),
          },
        ],
      );
    } else {
      setVisited(bar.id, false);
    }
  };

  return (
    <View className="flex-1 bg-ink">
      <AppBackground />
      {/* Grabber hinting the sheet is swipe-to-dismiss. */}
      <View className="items-center pt-2">
        <View className="h-1.5 w-10 rounded-full bg-white/25" />
      </View>
      <View className="flex-row justify-end px-4 pt-2">
        <Pressable
          onPress={onClose}
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
      <ScrollView contentContainerStyle={{ padding: 16, paddingBottom: 40 }}>
        <Text className="text-2xl font-extrabold text-white">{bar.name}</Text>
        <Text className="mt-1 text-sm font-semibold text-primary">
          {bar.neighborhood}
        </Text>

        {bar.tags?.length ? (
          <View className="mt-2 flex-row flex-wrap">
            {bar.tags.map((tag) => (
              <View
                key={tag}
                className="mb-1 mr-2 rounded-full border border-white/10 bg-white/[0.08] px-3 py-1"
              >
                <Text className="text-xs font-medium text-gray-300">{tag}</Text>
              </View>
            ))}
          </View>
        ) : null}

        <Pressable
          onPress={openDirections}
          className="mt-2 flex-row items-start active:opacity-70"
        >
          <Ionicons name="location-outline" size={16} color="#9ca3af" />
          <Text className="ml-1 flex-1 text-sm text-gray-400">
            {bar.address}
          </Text>
        </Pressable>

        {bar.description ? (
          <Text className="mt-3 text-sm leading-5 text-gray-300">
            {bar.description}
          </Text>
        ) : null}

        <Pressable
          onPress={toggleVisited}
          accessibilityRole="checkbox"
          accessibilityState={{ checked: visited }}
          accessibilityLabel="Visited"
          className="mt-5 active:opacity-80"
        >
          <Glass radius={16} bordered className="flex-row items-center justify-between px-4 py-3">
          <View className="flex-1 pr-3">
            <Text className="text-base font-semibold text-white">Visited</Text>
            <Text className="mt-0.5 text-xs text-gray-400">
              {visited ? "You've been here" : "Tap if you've been here"}
            </Text>
          </View>
          <Ionicons
            name={visited ? "checkbox" : "square-outline"}
            size={28}
            color={visited ? "#22c55e" : "#6b7280"}
          />
          </Glass>
        </Pressable>

        <View className="mt-4 mb-4 flex-row items-center justify-between rounded-2xl border border-primary/30 bg-primary/15 px-4 py-3">
          <Text className="flex-1 pr-3 text-sm font-medium text-white">
            {isTargetToday
              ? "Today's drinks"
              : `Drinks on ${formatDayKey(targetDay)}`}
          </Text>
          <CountUp
            value={total}
            duration={420}
            className="text-2xl font-extrabold text-primary"
          />
        </View>

        <Text className="mb-3 text-base font-bold text-white">Log a drink</Text>
        <DrinkLogger
          visit={visit}
          onLog={(type) => logDrink(bar.id, type, targetDay)}
          onRemove={(type) => removeDrink(bar.id, type, targetDay)}
        />

        <NotesSection
          // Remount when the visit appears/disappears so the draft resets.
          key={visit?.id ?? "no-visit"}
          note={visit?.note}
          editable={visit !== undefined}
          onCommit={(note) => setVisitNote(bar.id, targetDay, note)}
        />
      </ScrollView>
      {/* The modal covers the root layout's toast, so mount one here too. */}
      <BadgeToast />
    </View>
  );
}
