import { BlurView } from "expo-blur";
import { GlassView, isLiquidGlassAvailable } from "expo-glass-effect";
import { type ReactNode } from "react";
import { View, type ViewStyle } from "react-native";

// Resolved once at module load: true only on iOS 26+ where Apple's native
// Liquid Glass is available. Everywhere else we fall back to a frosted
// BlurView, which reads as glass on iOS 15+ and Android.
const LIQUID_GLASS = isLiquidGlassAvailable();

type GlassProps = {
  children?: ReactNode;
  /** Utility classes for the surface (padding, radius, border, layout). */
  className?: string;
  style?: ViewStyle;
  /** Blur strength for the BlurView fallback (ignored by native glass). */
  intensity?: number;
  /** Frost tint for the fallback. */
  tint?: "dark" | "light" | "default";
  /** Native Liquid Glass interactive sheen (iOS 26 only). */
  interactive?: boolean;
};

/**
 * A translucent "Liquid Glass" surface. On iOS 26+ it renders the real
 * native effect; otherwise a frosted BlurView with a hairline highlight.
 *
 * Note: never put an opacity utility on this component or its parents —
 * native GlassView errors on sub-1 opacity. Use a translucent background
 * fill or a child overlay to dim instead.
 */
export default function Glass({
  children,
  className = "",
  style,
  intensity = 40,
  tint = "dark",
  interactive = false,
}: GlassProps) {
  if (LIQUID_GLASS) {
    return (
      <GlassView
        // Remount when interactivity changes — it can't be toggled live.
        key={interactive ? "interactive" : "static"}
        isInteractive={interactive}
        glassEffectStyle="regular"
        style={style}
        className={`overflow-hidden ${className}`}
      >
        {children}
      </GlassView>
    );
  }

  return (
    <BlurView
      intensity={intensity}
      tint={tint}
      experimentalBlurMethod="dimezisBlurView"
      style={style}
      // A faint white fill + hairline border give the frosted edge highlight
      // that sells the glass look over the dark gradient backdrop.
      className={`overflow-hidden border border-white/10 bg-white/[0.06] ${className}`}
    >
      {children}
    </BlurView>
  );
}

/** Convenience: a full-bleed glass layer behind absolutely-positioned content. */
export function GlassFill({
  className = "",
  intensity = 40,
  tint = "dark",
}: Pick<GlassProps, "className" | "intensity" | "tint">) {
  return (
    <View
      pointerEvents="none"
      style={{ position: "absolute", inset: 0 } as ViewStyle}
    >
      <Glass intensity={intensity} tint={tint} className={`flex-1 ${className}`} />
    </View>
  );
}
