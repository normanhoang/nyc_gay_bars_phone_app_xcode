import { Ionicons } from "@expo/vector-icons";
import { useState } from "react";
import { Pressable, Text, TextInput, View } from "react-native";
import { drinkEmoji, PRESET_DRINKS } from "../lib/drinks";
import { lightTap } from "../lib/haptics";
import type { Visit } from "../lib/types";
import Glass from "./Glass";

type Props = {
  visit?: Visit;
  onLog: (type: string) => void;
  onRemove: (type: string) => void;
};

function countFor(visit: Visit | undefined, type: string): number {
  if (!visit) return 0;
  const entry = visit.drinks.find(
    (d) => d.type.toLowerCase() === type.toLowerCase(),
  );
  return entry?.count ?? 0;
}

function DrinkRow({
  type,
  count,
  onLog,
  onRemove,
}: {
  type: string;
  count: number;
  onLog: () => void;
  onRemove: () => void;
}) {
  return (
    <Glass radius={16} className="mb-3 flex-row items-center justify-between px-4 py-3">
      <View className="flex-1 flex-row items-center">
        <Text className="mr-3 text-2xl">{drinkEmoji(type)}</Text>
        <Text className="text-base font-medium text-white">{type}</Text>
      </View>

      <View className="flex-row items-center">
        <Pressable
          onPress={() => {
            lightTap();
            onRemove();
          }}
          disabled={count === 0}
          accessibilityRole="button"
          accessibilityLabel={`Remove ${type}`}
          className={
            count === 0
              ? "h-9 w-9 items-center justify-center rounded-full border border-white/10 bg-white/[0.06] opacity-40"
              : "h-9 w-9 items-center justify-center rounded-full border border-white/10 bg-white/[0.12] active:opacity-70"
          }
        >
          <Ionicons name="remove" size={20} color="#ffffff" />
        </Pressable>

        <Text className="w-8 text-center text-base font-bold text-white">
          {count}
        </Text>

        <Pressable
          onPress={() => {
            lightTap();
            onLog();
          }}
          accessibilityRole="button"
          accessibilityLabel={`Add ${type}`}
          className="h-9 w-9 items-center justify-center rounded-full bg-primary active:opacity-70"
        >
          <Ionicons name="add" size={20} color="#ffffff" />
        </Pressable>
      </View>
    </Glass>
  );
}

export default function DrinkLogger({ visit, onLog, onRemove }: Props) {
  const [custom, setCustom] = useState("");

  // Custom drink types present in the visit but not in the preset list.
  const customTypes = (visit?.drinks ?? [])
    .map((d) => d.type)
    .filter(
      (t) =>
        !PRESET_DRINKS.some((p) => p.toLowerCase() === t.toLowerCase()),
    );

  const addCustom = () => {
    const name = custom.trim();
    if (!name) return;
    lightTap();
    onLog(name);
    setCustom("");
  };

  return (
    <View>
      {PRESET_DRINKS.map((type) => (
        <DrinkRow
          key={type}
          type={type}
          count={countFor(visit, type)}
          onLog={() => onLog(type)}
          onRemove={() => onRemove(type)}
        />
      ))}

      {customTypes.map((type) => (
        <DrinkRow
          key={type}
          type={type}
          count={countFor(visit, type)}
          onLog={() => onLog(type)}
          onRemove={() => onRemove(type)}
        />
      ))}

      <Glass radius={16} className="flex-row items-center px-4 py-3">
        <TextInput
          value={custom}
          onChangeText={setCustom}
          onSubmitEditing={addCustom}
          placeholder="Add a custom drink…"
          placeholderTextColor="#6b7280"
          returnKeyType="done"
          className="flex-1 py-2 text-base text-white"
        />
        <Pressable
          onPress={addCustom}
          className="ml-2 flex-row items-center rounded-full bg-primary px-3 py-2 active:opacity-70"
        >
          <Ionicons name="add" size={16} color="#ffffff" />
          <Text className="ml-1 text-sm font-semibold text-white">Add</Text>
        </Pressable>
      </Glass>
    </View>
  );
}
