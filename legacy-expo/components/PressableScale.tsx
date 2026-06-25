import { type ReactNode } from "react";
import { Pressable, type PressableProps } from "react-native";
import Animated, {
  useAnimatedStyle,
  useSharedValue,
  withSpring,
} from "react-native-reanimated";

const PRESS_SPRING = { damping: 15, stiffness: 400, mass: 0.5 };

type Props = PressableProps & {
  children?: ReactNode;
  className?: string;
  /** Scale at full press (default 0.97). */
  scaleTo?: number;
};

/**
 * A Pressable that springs down slightly while held — the Apple "squish".
 * The `className` goes on the inner Animated.View, which is both the scaling
 * layer and the element wrapping the children, so layout utilities like
 * `flex-row` actually shape the content (a bare Animated.View defaults to a
 * column). The Pressable stays a layout-neutral touch target. Reanimated
 * applies the transform style; NativeWind interop covers the className.
 */
export default function PressableScale({
  children,
  className,
  scaleTo = 0.97,
  onPressIn,
  onPressOut,
  ...rest
}: Props) {
  const scale = useSharedValue(1);
  const style = useAnimatedStyle(() => ({
    transform: [{ scale: scale.value }],
  }));

  return (
    <Pressable
      onPressIn={(e) => {
        scale.value = withSpring(scaleTo, PRESS_SPRING);
        onPressIn?.(e);
      }}
      onPressOut={(e) => {
        scale.value = withSpring(1, PRESS_SPRING);
        onPressOut?.(e);
      }}
      {...rest}
    >
      <Animated.View className={className} style={style}>
        {children}
      </Animated.View>
    </Pressable>
  );
}
