import { Pressable, Text, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useBadges } from "../lib/BadgesContext";
import Glass from "./Glass";

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
        className="active:opacity-80"
      >
        <Glass
          radius={24}
          bordered
          borderColor="rgba(224,33,138,0.5)"
          className="flex-row items-center px-4 py-3 shadow-lg"
        >
          <Text className="mr-3 text-2xl">{badge.emoji}</Text>
          <View className="shrink">
            <Text className="text-xs uppercase tracking-wide text-gray-300">
              Badge unlocked
            </Text>
            <Text className="text-base font-bold text-white">{badge.title}</Text>
          </View>
        </Glass>
      </Pressable>
    </View>
  );
}
