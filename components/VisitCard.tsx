import { Ionicons } from "@expo/vector-icons";
import { Alert, Pressable, Text, View } from "react-native";
import { drinkEmoji } from "../lib/drinks";
import { getBarById } from "../lib/bars";
import type { Visit } from "../lib/types";
import { getDrinkTotal } from "../lib/VisitsContext";

type Props = {
  visit: Visit;
  onDelete: () => void;
};

function formatDate(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString(undefined, {
    weekday: "short",
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

export default function VisitCard({ visit, onDelete }: Props) {
  const bar = getBarById(visit.barId);
  const total = getDrinkTotal(visit);

  const confirmDelete = () => {
    Alert.alert(
      "Delete this entry?",
      `This will remove ${total} ${total === 1 ? "drink" : "drinks"} logged at ${
        bar?.name ?? "this bar"
      } on ${formatDate(visit.date)}.`,
      [
        { text: "Cancel", style: "cancel" },
        { text: "Delete", style: "destructive", onPress: onDelete },
      ],
    );
  };

  return (
    <View className="mb-3 rounded-2xl bg-ink-card p-4">
      <View className="flex-row items-start justify-between">
        <View className="flex-1 pr-3">
          <Text className="text-base font-semibold text-white">
            {bar?.name ?? "Unknown bar"}
          </Text>
          {bar ? (
            <Text className="mt-0.5 text-xs font-medium text-primary">
              {bar.neighborhood}
            </Text>
          ) : null}
          <Text className="mt-1 text-xs text-gray-400">
            {formatDate(visit.date)}
          </Text>
        </View>

        <View className="items-end">
          <Text className="text-lg font-extrabold text-primary">{total}</Text>
          <Text className="text-[10px] uppercase tracking-wide text-gray-400">
            {total === 1 ? "drink" : "drinks"}
          </Text>
        </View>
      </View>

      <View className="mt-3 flex-row flex-wrap">
        {visit.drinks.map((d) => (
          <View
            key={d.type}
            className="mb-2 mr-2 flex-row items-center rounded-full bg-ink-soft px-3 py-1"
          >
            <Text className="mr-1 text-sm">{drinkEmoji(d.type)}</Text>
            <Text className="text-sm text-white">{d.type}</Text>
            <Text className="ml-1.5 text-sm font-bold text-primary">
              ×{d.count}
            </Text>
          </View>
        ))}
      </View>

      {visit.note ? (
        <Text className="mb-2 text-sm italic text-gray-400">
          “{visit.note}”
        </Text>
      ) : null}

      <Pressable
        onPress={confirmDelete}
        className="mt-1 flex-row items-center self-start active:opacity-60"
      >
        <Ionicons name="trash-outline" size={14} color="#9ca3af" />
        <Text className="ml-1 text-xs text-gray-400">Delete</Text>
      </Pressable>
    </View>
  );
}
