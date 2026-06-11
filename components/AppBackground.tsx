import { LinearGradient } from "expo-linear-gradient";
import { View } from "react-native";

/**
 * Full-screen gradient backdrop. Glass surfaces need colour and contrast
 * behind them to refract — a flat near-black makes blur invisible — so the
 * whole app sits over a deep indigo→ink wash with a faint magenta top glow.
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
        colors={["#241026", "#100a18", "#0b0b12"]}
        locations={[0, 0.45, 1]}
        start={{ x: 0.1, y: 0 }}
        end={{ x: 0.9, y: 1 }}
        style={{ flex: 1 }}
      />
      {/* Soft magenta glow anchored top-right for depth. */}
      <LinearGradient
        colors={["rgba(224,33,138,0.18)", "rgba(224,33,138,0)"]}
        start={{ x: 1, y: 0 }}
        end={{ x: 0.2, y: 0.5 }}
        style={{ position: "absolute", top: 0, left: 0, right: 0, height: "55%" }}
      />
    </View>
  );
}
