import { Pressable, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useBadges } from "../lib/BadgesContext";

/**
 * Top-of-screen banner announcing freshly earned badges, one at a time.
 * Pure render — timing and haptics live in BadgesContext, so this can be
 * mounted in multiple places (root layout + modals, which cover the root).
 */
export default function BadgeToast() {
  const { unlocked, dismissUnlocked } = useBadges();
  const insets = useSafeAreaInsets();
  const badge = unlocked[0];

  if (!badge) return null;

  return (
    <View
      pointerEvents="box-none"
      style={{ position: "absolute", top: insets.top + 8, left: 0, right: 0 }}
      className="items-center px-6"
    >
      <Pressable
        onPress={dismissUnlocked}
        accessibilityRole="alert"
        className="flex-row items-center rounded-2xl border border-primary/40 bg-ink-card px-4 py-3 shadow-lg active:opacity-80"
      >
        <Text className="mr-3 text-2xl">{badge.emoji}</Text>
        <View className="shrink">
          <Text className="text-xs uppercase tracking-wide text-gray-400">
            Badge unlocked
          </Text>
          <Text className="text-base font-bold text-white">{badge.title}</Text>
        </View>
      </Pressable>
    </View>
  );
}
