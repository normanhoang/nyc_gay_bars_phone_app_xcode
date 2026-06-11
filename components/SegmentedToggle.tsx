import { useEffect, useState } from "react";
import { Pressable, Text } from "react-native";
import Animated, {
  useAnimatedStyle,
  useSharedValue,
  withSpring,
} from "react-native-reanimated";
import Glass from "./Glass";

const CHIP_SPRING = { damping: 18, stiffness: 220, mass: 0.6 };

export type SegmentedOption<T extends string> = {
  value: T;
  label: string;
};

type Props<T extends string> = {
  options: SegmentedOption<T>[];
  value: T;
  onChange: (value: T) => void;
};

export default function SegmentedToggle<T extends string>({
  options,
  value,
  onChange,
}: Props<T>) {
  // Per-option layout within the pill, measured onLayout, drives the chip.
  const [layouts, setLayouts] = useState<{ x: number; width: number }[]>([]);
  const chipX = useSharedValue(0);
  const chipWidth = useSharedValue(0);
  const chipShown = useSharedValue(0);

  const selectedIndex = options.findIndex((opt) => opt.value === value);

  useEffect(() => {
    const target = layouts[selectedIndex];
    if (!target) return;
    if (chipShown.value === 0) {
      // First measurement: place the chip without animating.
      chipX.value = target.x;
      chipWidth.value = target.width;
      chipShown.value = 1;
    } else {
      chipX.value = withSpring(target.x, CHIP_SPRING);
      chipWidth.value = withSpring(target.width, CHIP_SPRING);
    }
  }, [selectedIndex, layouts, chipX, chipWidth, chipShown]);

  const chipStyle = useAnimatedStyle(() => ({
    opacity: chipShown.value,
    left: chipX.value,
    width: chipWidth.value,
  }));

  return (
    <Glass radius={999} bordered className="flex-row p-1">
      {/* Primary pill that slides under the selected option. Plain style
          objects — className on Animated.View risks dropped NativeWind
          interop like other non-core components. */}
      <Animated.View
        pointerEvents="none"
        style={[
          {
            position: "absolute",
            top: 4,
            bottom: 4,
            borderRadius: 999,
            backgroundColor: "#e0218a",
          },
          chipStyle,
        ]}
      />
      {options.map((opt, index) => {
        const active = opt.value === value;
        return (
          <Pressable
            key={opt.value}
            onPress={() => onChange(opt.value)}
            onLayout={(e) => {
              const { x, width } = e.nativeEvent.layout;
              setLayouts((prev) => {
                const next = [...prev];
                next[index] = { x, width };
                return next;
              });
            }}
            accessibilityRole="tab"
            accessibilityState={{ selected: active }}
            className="flex-1 items-center rounded-full py-2"
          >
            <Text
              className={
                active
                  ? "text-sm font-semibold text-white"
                  : "text-sm font-semibold text-gray-200"
              }
            >
              {opt.label}
            </Text>
          </Pressable>
        );
      })}
    </Glass>
  );
}
