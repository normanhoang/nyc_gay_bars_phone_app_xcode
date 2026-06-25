import { BlurView } from "expo-blur";
import { GlassView, isLiquidGlassAvailable } from "expo-glass-effect";
import { type ReactNode } from "react";
import { StyleSheet, View } from "react-native";

// Resolved once at module load: true only on iOS 26+ where Apple's native
// Liquid Glass is available. Everywhere else we fall back to a frosted
// BlurView, which reads as glass on iOS 15+ and Android.
const LIQUID_GLASS = isLiquidGlassAvailable();

type GlassProps = {
  children?: ReactNode;
  /** Layout/padding utility classes only — radius and borders are props. */
  className?: string;
  /**
   * Corner radius, applied to both the wrapper and the native glass layer.
   * Passing it down lets iOS 26 glass shape itself (smooth rim) instead of
   * being rect-clipped by the wrapper's corner mask, which looks jagged.
   */
  radius?: number;
  /** Draw a hairline overlay border (crisper than 1px utility borders). */
  bordered?: boolean;
  borderColor?: string;
  /** Blur strength for the BlurView fallback (ignored by native glass). */
  intensity?: number;
  /** Frost tint for the fallback. */
  tint?: "dark" | "light" | "default";
  /** Native Liquid Glass interactive sheen (iOS 26 only). */
  interactive?: boolean;
};

/**
 * A translucent "Liquid Glass" surface for chrome and controls (search bars,
 * toggles, buttons, toasts, tab/header backgrounds). On iOS 26+ it renders
 * the real native effect; otherwise a frosted BlurView.
 *
 * Static *content* panels (stat cards, calendar, visit cards, badges) should
 * NOT use this — native glass draws an un-disableable luminous rim that reads
 * as a border. Use a plain `View` with `bg-white/[0.05]` instead.
 *
 * Note: never put an opacity utility on this component or its parents —
 * native GlassView errors on sub-1 opacity. Dim with a translucent fill or
 * an overlay child instead.
 */
export default function Glass({
  children,
  className = "",
  radius,
  bordered = false,
  borderColor = "rgba(255,255,255,0.16)",
  intensity = 40,
  tint = "dark",
  interactive = false,
}: GlassProps) {
  return (
    <View
      className={`overflow-hidden ${className}`}
      style={radius !== undefined ? { borderRadius: radius } : undefined}
    >
      {LIQUID_GLASS ? (
        <GlassView
          // Remount when interactivity changes — it can't be toggled live.
          key={interactive ? "interactive" : "static"}
          isInteractive={interactive}
          glassEffectStyle="regular"
          style={[
            StyleSheet.absoluteFill,
            radius !== undefined ? { borderRadius: radius } : null,
          ]}
        />
      ) : (
        <BlurView
          intensity={intensity}
          tint={tint}
          experimentalBlurMethod="dimezisBlurView"
          style={StyleSheet.absoluteFill}
        />
      )}
      {/* Faint white fill lifts contrast over the dark gradient backdrop. */}
      <View
        pointerEvents="none"
        style={StyleSheet.absoluteFill}
        className="bg-white/[0.07]"
      />
      {bordered ? (
        <View
          pointerEvents="none"
          style={[
            StyleSheet.absoluteFill,
            {
              borderRadius: radius,
              borderWidth: StyleSheet.hairlineWidth,
              borderColor,
            },
          ]}
        />
      ) : null}
      {children}
    </View>
  );
}
