import { LinearGradient } from "expo-linear-gradient";
import { View } from "react-native";

/**
 * Full-screen gradient backdrop. Glass surfaces need colour and contrast
 * behind them to refract — a flat near-black makes blur invisible — so the
 * whole app sits over a deep plum→ink wash that keeps a visible tint all the
 * way down (an early cut to pure black reads as the gradient "stopping"
 * midway), plus a magenta glow up top and a faint violet rise from below.
 *
 * Render as the first child of a screen root (absolutely filled); content
 * stacks on top.
 */
export default function AppBackground() {
  return (
    <View
      pointerEvents="none"
      style={{ position: "absolute", top: 0, left: 0, right: 0, bottom: 0 }}
    >
      <LinearGradient
        colors={["#2a1033", "#1a0f26", "#120f1d"]}
        locations={[0, 0.55, 1]}
        start={{ x: 0.1, y: 0 }}
        end={{ x: 0.9, y: 1 }}
        style={{ flex: 1 }}
      />
      {/* Soft magenta glow anchored top-right for depth. */}
      <LinearGradient
        colors={["rgba(224,33,138,0.18)", "rgba(224,33,138,0)"]}
        start={{ x: 1, y: 0 }}
        end={{ x: 0.2, y: 0.6 }}
        style={{ position: "absolute", top: 0, left: 0, right: 0, height: "60%" }}
      />
      {/* Faint violet rise from the bottom so the lower half never goes flat. */}
      <LinearGradient
        colors={["rgba(110,60,190,0)", "rgba(110,60,190,0.14)"]}
        start={{ x: 0.3, y: 0 }}
        end={{ x: 0.7, y: 1 }}
        style={{
          position: "absolute",
          bottom: 0,
          left: 0,
          right: 0,
          height: "45%",
        }}
      />
    </View>
  );
}
