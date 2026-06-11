import { useState } from "react";
import {
  ActivityIndicator,
  Alert,
  Image,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  Text,
  TextInput,
} from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { supabase } from "../lib/supabase";

export default function SignInScreen() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [loading, setLoading] = useState(false);
  const insets = useSafeAreaInsets();

  const submit = async () => {
    if (!email.trim() || !password) return;
    setLoading(true);
    try {
      if (mode === "signin") {
        const { error } = await supabase.auth.signInWithPassword({
          email: email.trim(),
          password,
        });
        if (error) Alert.alert("Sign in failed", error.message);
      } else {
        const { error } = await supabase.auth.signUp({
          email: email.trim(),
          password,
        });
        if (error) Alert.alert("Sign up failed", error.message);
        else
          Alert.alert(
            "Check your email",
            "Click the confirmation link, then sign in.",
          );
      }
    } finally {
      setLoading(false);
    }
  };

  return (
    <KeyboardAvoidingView
      className="flex-1 bg-ink"
      behavior={Platform.OS === "ios" ? "padding" : undefined}
    >
      <ScrollView
        // Content is anchored to the top (not centered): the keyboard's
        // height fluctuates per keystroke (QuickType/autofill bar), and a
        // centered layout re-centers on every fluctuation — visible jiggle.
        contentContainerStyle={{
          paddingTop: insets.top + 40,
          paddingBottom: insets.bottom + 24,
          paddingHorizontal: 32,
        }}
        keyboardShouldPersistTaps="handled"
      >
        <Image
          source={require("../assets/icon.png")}
          className="mb-4 h-[224px] w-[224px] self-center rounded-[40px]"
          accessibilityLabel="NYC Gay Bars app icon"
        />
        <Text className="mb-1 text-3xl font-extrabold text-white">
          NYC Gay Bars
        </Text>
        <Text className="mb-10 text-sm text-gray-500">
          {mode === "signin"
            ? "Sign in to sync your drink history."
            : "Create an account to get started."}
        </Text>

        <TextInput
          value={email}
          onChangeText={setEmail}
          placeholder="Email"
          placeholderTextColor="#4b5563"
          keyboardType="email-address"
          autoCapitalize="none"
          autoCorrect={false}
          returnKeyType="next"
          className="mb-3 rounded-2xl bg-ink-card px-4 py-4 text-base text-white"
        />
        <TextInput
          value={password}
          onChangeText={setPassword}
          placeholder="Password"
          placeholderTextColor="#4b5563"
          secureTextEntry
          returnKeyType="done"
          onSubmitEditing={submit}
          className="mb-6 rounded-2xl bg-ink-card px-4 py-4 text-base text-white"
        />

        <Pressable
          onPress={submit}
          disabled={loading}
          className="mb-4 items-center rounded-2xl bg-primary py-4 active:opacity-70"
          style={loading ? { opacity: 0.6 } : undefined}
        >
          {loading ? (
            <ActivityIndicator color="#ffffff" />
          ) : (
            <Text className="text-base font-bold text-white">
              {mode === "signin" ? "Sign In" : "Create Account"}
            </Text>
          )}
        </Pressable>

        <Pressable
          onPress={() => setMode(mode === "signin" ? "signup" : "signin")}
          className="items-center py-2"
        >
          <Text className="text-sm text-gray-400">
            {mode === "signin"
              ? "Don't have an account? "
              : "Already have an account? "}
            <Text className="text-primary">
              {mode === "signin" ? "Sign Up" : "Sign In"}
            </Text>
          </Text>
        </Pressable>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}
