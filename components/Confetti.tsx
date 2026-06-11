import { useEffect, useMemo } from "react";
import { Dimensions, View } from "react-native";
import Animated, {
  Easing,
  useAnimatedStyle,
  useSharedValue,
  withDelay,
  withTiming,
} from "react-native-reanimated";

const COLORS = [
  "#e40303",
  "#ff8c00",
  "#ffed00",
  "#008026",
  "#24408e",
  "#732982",
  "#ff4da6",
  "#5bcefa",
  "#f5a9b8",
  "#ffffff",
];

const COUNT = 48;
const HEIGHT = 820;
const { width: SCREEN_W } = Dimensions.get("window");

type PieceParams = {
  startX: number;
  launch: number;
  drift: number;
  fall: number;
  delay: number;
  spin: number;
  w: number;
  h: number;
  color: string;
  duration: number;
};

function makePiece(i: number): PieceParams {
  const rand = (min: number, max: number) => min + Math.random() * (max - min);
  // A quarter of the pieces are long thin streamers for variety.
  const streamer = Math.random() < 0.25;
  const base = rand(8, 13);
  return {
    startX: SCREEN_W / 2 + rand(-44, 44),
    launch: rand(70, 190), // initial upward velocity → firework arc
    drift: rand(-SCREEN_W / 1.6, SCREEN_W / 1.6),
    fall: rand(540, 860),
    delay: rand(0, 140),
    spin: rand(-760, 760),
    w: streamer ? rand(4, 7) : base,
    h: streamer ? rand(16, 28) : base * 0.7,
    color: COLORS[i % COLORS.length],
    duration: rand(1300, 2100),
  };
}

function Piece({ p }: { p: PieceParams }) {
  const t = useSharedValue(0);
  useEffect(() => {
    t.value = withDelay(
      p.delay,
      withTiming(1, { duration: p.duration, easing: Easing.linear }),
    );
  }, [t, p.delay, p.duration]);

  const style = useAnimatedStyle(() => {
    // Gravity arc: rise by `launch`, then fall by `fall * t²`.
    const y = -p.launch * t.value + p.fall * t.value * t.value;
    return {
      transform: [
        { translateX: p.drift * t.value },
        { translateY: y },
        { rotate: `${p.spin * t.value}deg` },
      ],
      opacity: t.value < 0.82 ? 1 : Math.max(0, 1 - (t.value - 0.82) / 0.18),
    };
  });

  return (
    <Animated.View
      style={[
        {
          position: "absolute",
          left: p.startX,
          top: 36,
          width: p.w,
          height: p.h,
          backgroundColor: p.color,
          borderRadius: 2,
        },
        style,
      ]}
    />
  );
}

/**
 * An expressive one-shot confetti firework: pieces burst up from the top-centre
 * and rain down with gravity, spin, and streamers. Plays once on mount;
 * absolutely positioned and non-interactive. Pure Reanimated — no native lib,
 * so it works in Expo Go.
 */
export default function Confetti() {
  const pieces = useMemo(
    () => Array.from({ length: COUNT }, (_, i) => makePiece(i)),
    [],
  );
  return (
    <View
      pointerEvents="none"
      style={{ position: "absolute", top: 0, left: 0, right: 0, height: HEIGHT }}
    >
      {pieces.map((p, i) => (
        <Piece key={i} p={p} />
      ))}
    </View>
  );
}
