import { useEffect } from "react";
import { Pressable, Text, View } from "react-native";
import Animated, {
  useAnimatedStyle,
  useSharedValue,
  withDelay,
  withSequence,
  withSpring,
  withTiming,
} from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useBadges } from "../lib/BadgesContext";
import { MILESTONE_BADGE_IDS } from "../lib/stats";
import Confetti from "./Confetti";
import Glass from "./Glass";

const ENTER_SPRING = { damping: 16, stiffness: 200, mass: 0.7 };

/**
 * Top-of-screen banner announcing freshly earned badges, one at a time. The
 * banner springs down and the emoji pops; prestige badges
 * ([[MILESTONE_BADGE_IDS]]) also rain confetti. Timing/haptics live in
 * BadgesContext, so this stays a pure render and can be mounted in several
 * places (root layout + modals, which cover the root).
 */
export default function BadgeToast() {
  const { unlocked, dismissUnlocked } = useBadges();
  const insets = useSafeAreaInsets();
  const badge = unlocked[0];
  const milestone = badge ? MILESTONE_BADGE_IDS.has(badge.id) : false;

  // Drive entrance from the badge id so each queued badge re-animates.
  const enter = useSharedValue(0);
  const pop = useSharedValue(0);
  useEffect(() => {
    if (!badge) return;
    enter.value = 0;
    pop.value = 0;
    enter.value = withSpring(1, ENTER_SPRING);
    pop.value = withDelay(
      120,
      withSequence(
        withTiming(1, { duration: 220 }),
        withSpring(0, { damping: 6, stiffness: 180 }),
      ),
    );
  }, [badge, enter, pop]);

  const bannerStyle = useAnimatedStyle(() => ({
    opacity: enter.value,
    transform: [{ translateY: (1 - enter.value) * -24 }],
  }));
  const emojiStyle = useAnimatedStyle(() => ({
    transform: [{ scale: 1 + pop.value * 0.4 }, { rotate: `${pop.value * 8}deg` }],
  }));

  if (!badge) return null;

  return (
    <View
      pointerEvents="box-none"
      style={{ position: "absolute", top: insets.top + 8, left: 0, right: 0 }}
      className="items-center px-6"
    >
      {milestone ? <Confetti key={badge.id} /> : null}
      <Animated.View style={bannerStyle}>
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
            <Animated.Text style={emojiStyle} className="mr-3 text-2xl">
              {badge.emoji}
            </Animated.Text>
            <View className="shrink">
              <Text className="text-xs uppercase tracking-wide text-gray-300">
                {milestone ? "Milestone unlocked" : "Badge unlocked"}
              </Text>
              <Text className="text-base font-bold text-white">
                {badge.title}
              </Text>
            </View>
          </Glass>
        </Pressable>
      </Animated.View>
    </View>
  );
}
