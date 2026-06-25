import { LinearGradient } from "expo-linear-gradient";
import { useEffect } from "react";
import { View } from "react-native";
import Animated, {
  useAnimatedStyle,
  useSharedValue,
  withDelay,
  withSpring,
} from "react-native-reanimated";

const FILL_SPRING = { damping: 20, stiffness: 140, mass: 0.7 };

type Props = {
  /** 0–1 fraction filled. */
  progress: number;
  /** Stagger the fill animation (ms) so rows cascade. */
  delay?: number;
};

/**
 * A slim rounded track with a magenta→violet gradient fill that springs out
 * to `progress` on mount — matches the badge tile wash.
 */
export default function ProgressBar({ progress, delay = 0 }: Props) {
  const clamped = Math.max(0, Math.min(1, progress));
  const w = useSharedValue(0);

  useEffect(() => {
    w.value = withDelay(delay, withSpring(clamped, FILL_SPRING));
  }, [clamped, delay, w]);

  const style = useAnimatedStyle(() => ({
    width: `${w.value * 100}%`,
  }));

  return (
    <View className="h-2 overflow-hidden rounded-full bg-white/10">
      <Animated.View style={style} className="h-full">
        <LinearGradient
          colors={["#e0218a", "#a23bd6"]}
          start={{ x: 0, y: 0 }}
          end={{ x: 1, y: 0 }}
          style={{ flex: 1, borderRadius: 999 }}
        />
      </Animated.View>
    </View>
  );
}
