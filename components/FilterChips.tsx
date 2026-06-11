import { useEffect, useRef } from "react";
import {
  type LayoutChangeEvent,
  Pressable,
  ScrollView,
  Text,
  View,
} from "react-native";

type Props = {
  options: string[];
  value: string;
  onChange: (value: string) => void;
};

/**
 * Horizontal single-select filter chips. The first option (e.g. "All") is
 * pinned on the left and always visible; the rest scroll horizontally beside it.
 */
export default function FilterChips({ options, value, onChange }: Props) {
  const scrollRef = useRef<ScrollView>(null);
  // x-offset of each scrollable chip within the scroll content, set on layout.
  const positions = useRef<Record<string, number>>({});

  const [pinned, ...rest] = options;

  const scrollToSelected = () => {
    // Pinned option (e.g. "All") is always visible — don't move the row for
    // it here; selecting it programmatically (map zoom-out) keeps the user's
    // scroll position, and an explicit tap resets the row in onPress instead.
    if (value === pinned) return;
    const x = positions.current[value];
    if (x !== undefined) {
      scrollRef.current?.scrollTo({ x: Math.max(x - 16, 0), animated: true });
    }
  };

  // When the chip order changes (e.g. proximity ordering kicks in after the
  // location resolves on first load), drop stale offsets so we don't scroll to
  // an old position. onLayout below repopulates them and reveals the selection.
  const optionsKey = rest.join("|");
  useEffect(() => {
    positions.current = {};
  }, [optionsKey]);

  // Reveal the selected chip when the selection changes via a chip/outline tap
  // (offsets are already measured, so this scrolls immediately).
  useEffect(() => {
    scrollToSelected();
  }, [value]);

  const renderChip = (opt: string, scrollable: boolean) => {
    const active = opt === value;
    return (
      <Pressable
        key={opt}
        onLayout={
          scrollable
            ? (e: LayoutChangeEvent) => {
                positions.current[opt] = e.nativeEvent.layout.x;
                // After a re-layout, keep the selected chip in view rather than
                // relying on a stale offset from the previous order.
                if (opt === value) scrollToSelected();
              }
            : undefined
        }
        onPress={() => {
          onChange(opt);
          // Explicit tap on the pinned chip resets the row to the far left.
          if (opt === pinned) {
            scrollRef.current?.scrollTo({ x: 0, animated: true });
          }
        }}
        className={
          active
            ? "mr-2 rounded-full border border-primary/60 bg-primary px-4 py-2"
            : "mr-2 rounded-full border border-white/10 bg-white/[0.08] px-4 py-2"
        }
      >
        <Text
          className={
            active
              ? "text-sm font-semibold text-white"
              : "text-sm font-semibold text-gray-300"
          }
        >
          {opt}
        </Text>
      </Pressable>
    );
  };

  return (
    <View className="flex-row items-center">
      {pinned !== undefined ? renderChip(pinned, false) : null}
      <ScrollView
        ref={scrollRef}
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={{ paddingRight: 16 }}
        style={{ flex: 1 }}
      >
        {rest.map((opt) => renderChip(opt, true))}
      </ScrollView>
    </View>
  );
}
