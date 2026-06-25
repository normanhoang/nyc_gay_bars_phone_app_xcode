import "../global.css";

import { Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { useEffect, useState } from "react";
import { StyleSheet, View } from "react-native";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { SafeAreaProvider } from "react-native-safe-area-context";
import BadgeToast from "../components/BadgeToast";
import Splash from "../components/Splash";
import { BadgesProvider } from "../lib/BadgesContext";
import { VisitsProvider } from "../lib/VisitsContext";

export default function RootLayout() {
  // The whole app mounts immediately and renders behind the splash, so the
  // first screen is fully loaded by the time the splash fades after 1.0s.
  const [showSplash, setShowSplash] = useState(true);

  useEffect(() => {
    const t = setTimeout(() => setShowSplash(false), 1000);
    return () => clearTimeout(t);
  }, []);

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <VisitsProvider>
          <BadgesProvider>
            <StatusBar style="light" />
            <Stack
              screenOptions={{
                headerStyle: { backgroundColor: "#0b0b12" },
                headerTintColor: "#ffffff",
                contentStyle: { backgroundColor: "#0b0b12" },
              }}
            >
              <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
              <Stack.Screen
                name="bar/[id]"
                options={{ presentation: "modal", headerShown: false }}
              />
              <Stack.Screen
                name="log/[day]"
                // Header hidden for the same reason as bar/[id]: the screen
                // renders its own title row with a glass close button.
                options={{ presentation: "modal", headerShown: false }}
              />
            </Stack>
            <BadgeToast />
            {showSplash ? (
              <View style={StyleSheet.absoluteFill} pointerEvents="none">
                <Splash />
              </View>
            ) : null}
          </BadgesProvider>
        </VisitsProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}
