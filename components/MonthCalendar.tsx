import { Ionicons } from "@expo/vector-icons";
import { useEffect, useState } from "react";
import { Pressable, Text, View } from "react-native";
import { dayKey } from "../lib/VisitsContext";

type Props = {
  /** dayKeys (see lib/VisitsContext.dayKey) that have logged visits. */
  markedDays: Set<string>;
  /** Currently selected dayKey. */
  selectedDay: string;
  onSelectDay: (day: string) => void;
};

const WEEKDAYS = ["S", "M", "T", "W", "T", "F", "S"];
const MONTHS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

function parseDayKey(key: string): { year: number; month: number } {
  const [y, m] = key.split("-").map(Number);
  return { year: y, month: m };
}

export default function MonthCalendar({
  markedDays,
  selectedDay,
  onSelectDay,
}: Props) {
  // Which month is on screen — starts on the selected day's month.
  const initial = parseDayKey(selectedDay);
  const [view, setView] = useState(initial);

  // Follow the selection when it changes from outside (e.g. the History tab
  // resetting to today on focus). Taps inside the grid are already in view.
  useEffect(() => {
    const { year, month } = parseDayKey(selectedDay);
    setView((v) =>
      v.year === year && v.month === month ? v : { year, month },
    );
  }, [selectedDay]);

  const today = dayKey();
  const firstWeekday = new Date(view.year, view.month, 1).getDay();
  const daysInMonth = new Date(view.year, view.month + 1, 0).getDate();

  // Leading blanks to align the 1st under the right weekday, then the days.
  const cells: (number | null)[] = [
    ...Array.from({ length: firstWeekday }, () => null),
    ...Array.from({ length: daysInMonth }, (_, i) => i + 1),
  ];

  const shiftMonth = (delta: number) => {
    const d = new Date(view.year, view.month + delta, 1);
    setView({ year: d.getFullYear(), month: d.getMonth() });
  };

  return (
    <View className="rounded-[32px] bg-white/[0.05] p-4">
      <View className="mb-3 flex-row items-center justify-between">
        <Pressable
          onPress={() => shiftMonth(-1)}
          hitSlop={10}
          accessibilityRole="button"
          accessibilityLabel="Previous month"
          className="h-8 w-8 items-center justify-center rounded-full active:opacity-60"
        >
          <Ionicons name="chevron-back" size={20} color="#ffffff" />
        </Pressable>
        <Text className="text-base font-bold text-white">
          {MONTHS[view.month]} {view.year}
        </Text>
        <Pressable
          onPress={() => shiftMonth(1)}
          hitSlop={10}
          accessibilityRole="button"
          accessibilityLabel="Next month"
          className="h-8 w-8 items-center justify-center rounded-full active:opacity-60"
        >
          <Ionicons name="chevron-forward" size={20} color="#ffffff" />
        </Pressable>
      </View>

      <View className="flex-row">
        {WEEKDAYS.map((w, i) => (
          <View key={i} className="flex-1 items-center pb-1">
            <Text className="text-xs font-semibold text-gray-500">{w}</Text>
          </View>
        ))}
      </View>

      <View className="flex-row flex-wrap">
        {cells.map((day, i) => {
          if (day === null) {
            return <View key={`b${i}`} className="h-11 w-[14.28%]" />;
          }
          const key = `${view.year}-${view.month}-${day}`;
          const selected = key === selectedDay;
          const isToday = key === today;
          const marked = markedDays.has(key);

          return (
            <Pressable
              key={key}
              onPress={() => onSelectDay(key)}
              className="h-11 w-[14.28%] items-center justify-center"
            >
              <View
                className={
                  selected
                    ? "h-9 w-9 items-center justify-center rounded-full bg-primary"
                    : isToday
                      ? "h-9 w-9 items-center justify-center rounded-full border border-gray-600"
                      : "h-9 w-9 items-center justify-center rounded-full"
                }
              >
                <Text
                  className={
                    selected
                      ? "text-sm font-bold text-white"
                      : "text-sm text-gray-200"
                  }
                >
                  {day}
                </Text>
              </View>
              <View
                className={
                  marked && !selected
                    ? "absolute bottom-1 h-1 w-1 rounded-full bg-primary"
                    : "absolute bottom-1 h-1 w-1 rounded-full bg-transparent"
                }
              />
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}
