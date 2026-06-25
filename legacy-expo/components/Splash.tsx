import { Image, View } from "react-native";
import AppBackground from "./AppBackground";

/**
 * Branded launch screen: the logo centered on the app gradient. Shown for a
 * brief moment on startup (see app/_layout.tsx) before the first tab renders.
 */
export default function Splash() {
  return (
    <View className="flex-1 items-center justify-center">
      <AppBackground />
      <Image
        // Transparent artwork (no baked background) so the logo floats on the
        // gradient with no tile edge. ~28% internal safe-zone padding, so it's
        // sized up and margin-trimmed to compensate (matches the old sign-in).
        source={require("../assets/splash-icon.png")}
        className="-my-8 h-[300px] w-[300px]"
        accessibilityLabel="NYC Gay Bars logo"
      />
    </View>
  );
}
