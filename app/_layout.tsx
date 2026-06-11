import "../global.css";

import type { Session } from "@supabase/supabase-js";
import { Stack } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { useEffect, useState } from "react";
import { ActivityIndicator, View } from "react-native";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { SafeAreaProvider } from "react-native-safe-area-context";
import BadgeToast from "../components/BadgeToast";
import { BadgesProvider } from "../lib/BadgesContext";
import { supabase } from "../lib/supabase";
import { VisitsProvider } from "../lib/VisitsContext";
import SignInScreen from "./sign-in";

export default function RootLayout() {
  // undefined = session check in-flight; null = signed out; Session = signed in
  const [session, setSession] = useState<Session | null | undefined>(undefined);

  useEffect(() => {
    supabase.auth
      .getSession()
      .then(({ data: { session } }) => setSession(session));
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session);
    });
    return () => subscription.unsubscribe();
  }, []);

  if (session === undefined) {
    return (
      <View
        style={{
          flex: 1,
          backgroundColor: "#0b0b12",
          justifyContent: "center",
          alignItems: "center",
        }}
      >
        <ActivityIndicator color="#e0218a" size="large" />
      </View>
    );
  }

  if (!session) {
    return (
      <GestureHandlerRootView style={{ flex: 1 }}>
        <SafeAreaProvider>
          <StatusBar style="light" />
          <SignInScreen />
        </SafeAreaProvider>
      </GestureHandlerRootView>
    );
  }

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <VisitsProvider userId={session.user.id}>
          <BadgesProvider userId={session.user.id}>
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
          </BadgesProvider>
        </VisitsProvider>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}
