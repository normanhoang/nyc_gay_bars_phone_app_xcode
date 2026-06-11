import { Ionicons } from "@expo/vector-icons";
import { Tabs } from "expo-router";
import { View } from "react-native";
import AppBackground from "../../components/AppBackground";
import Glass from "../../components/Glass";

export default function TabsLayout() {
  return (
    <View className="flex-1">
      <AppBackground />
      <Tabs
        screenOptions={{
          headerTransparent: true,
          headerStyle: { backgroundColor: "transparent" },
          headerBackground: () => <Glass className="flex-1" intensity={30} />,
          headerTintColor: "#ffffff",
          headerTitleStyle: { fontWeight: "700" },
          // Translucent frosted tab bar with a hairline top highlight.
          tabBarStyle: {
            backgroundColor: "transparent",
            borderTopWidth: 0.5,
            borderTopColor: "rgba(255,255,255,0.12)",
            elevation: 0,
          },
          tabBarBackground: () => <Glass className="flex-1" intensity={40} />,
          tabBarActiveTintColor: "#ff4da6",
          tabBarInactiveTintColor: "#9ca3af",
          sceneStyle: { backgroundColor: "transparent" },
        }}
      >
        <Tabs.Screen
          name="index"
          options={{
            title: "Explore",
            headerShown: false,
            tabBarIcon: ({ color, size }) => (
              <Ionicons name="beer" size={size} color={color} />
            ),
          }}
        />
        <Tabs.Screen
          name="stats"
          options={{
            title: "Stats",
            headerShown: false,
            tabBarIcon: ({ color, size }) => (
              <Ionicons name="stats-chart" size={size} color={color} />
            ),
          }}
        />
        <Tabs.Screen
          name="history"
          options={{
            title: "History",
            headerShown: false,
            tabBarIcon: ({ color, size }) => (
              <Ionicons name="time" size={size} color={color} />
            ),
          }}
        />
      </Tabs>
    </View>
  );
}
