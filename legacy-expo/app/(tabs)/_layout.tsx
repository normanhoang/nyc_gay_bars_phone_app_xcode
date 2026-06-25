import { Ionicons } from "@expo/vector-icons";
import {
  createMaterialTopTabNavigator,
  type MaterialTopTabBarProps,
} from "@react-navigation/material-top-tabs";
import { withLayoutContext } from "expo-router";
import { useEffect, useState } from "react";
import { Pressable, Text, View } from "react-native";
import Animated, {
  useAnimatedStyle,
  useSharedValue,
  withSpring,
} from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import AppBackground from "../../components/AppBackground";
import Glass from "../../components/Glass";
import { SetTabSwipeEnabledContext } from "../../components/TabSwipeContext";

// Swipeable bottom tabs: material-top-tabs gives the interactive page-follow
// drag (via react-native-pager-view); we pin it to the bottom and render our
// own floating glass pill as the tab bar.
const { Navigator } = createMaterialTopTabNavigator();
const MaterialTopTabs = withLayoutContext(Navigator);

const CHIP_SPRING = { damping: 18, stiffness: 220, mass: 0.6 };

function GlassTabBar({ state, descriptors, navigation }: MaterialTopTabBarProps) {
  const insets = useSafeAreaInsets();
  const [layouts, setLayouts] = useState<{ x: number; width: number }[]>([]);
  const chipX = useSharedValue(0);
  const chipWidth = useSharedValue(0);
  const chipShown = useSharedValue(0);

  useEffect(() => {
    const target = layouts[state.index];
    if (!target) return;
    if (chipShown.value === 0) {
      chipX.value = target.x;
      chipWidth.value = target.width;
      chipShown.value = 1;
    } else {
      chipX.value = withSpring(target.x, CHIP_SPRING);
      chipWidth.value = withSpring(target.width, CHIP_SPRING);
    }
  }, [state.index, layouts, chipX, chipWidth, chipShown]);

  const chipStyle = useAnimatedStyle(() => ({
    opacity: chipShown.value,
    left: chipX.value,
    width: chipWidth.value,
  }));

  return (
    <View
      pointerEvents="box-none"
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        bottom: Math.max(insets.bottom, 12) + 4,
        alignItems: "center",
      }}
    >
      <Glass radius={999} bordered intensity={50} className="flex-row p-1.5">
        {/* Frosted chip that slides under the active tab. Plain style, not
            className, since Animated.View isn't NativeWind-interop'd. */}
        <Animated.View
          pointerEvents="none"
          style={[
            {
              position: "absolute",
              top: 6,
              bottom: 6,
              borderRadius: 999,
              borderWidth: 1,
              borderColor: "rgba(255,255,255,0.25)",
              backgroundColor: "rgba(255,255,255,0.10)",
            },
            chipStyle,
          ]}
        />
        {state.routes.map((route, index) => {
          const { options } = descriptors[route.key];
          const focused = state.index === index;
          const color = focused ? "#ff4da6" : "#9ca3af";
          const label = (options.title ?? route.name) as string;

          return (
            <Pressable
              key={route.key}
              onPress={() => {
                if (!focused) navigation.navigate(route.name);
              }}
              onLayout={(e) => {
                const { x, width } = e.nativeEvent.layout;
                setLayouts((prev) => {
                  const next = [...prev];
                  next[index] = { x, width };
                  return next;
                });
              }}
              accessibilityRole="tab"
              accessibilityState={{ selected: focused }}
              accessibilityLabel={label}
              className="mx-0.5 items-center rounded-full px-5 py-2"
            >
              {options.tabBarIcon?.({ focused, color })}
              <Text style={{ color }} className="mt-0.5 text-[11px] font-semibold">
                {label}
              </Text>
            </Pressable>
          );
        })}
      </Glass>
    </View>
  );
}

export default function TabsLayout() {
  // Explore turns this off while its map is showing, so the pager doesn't
  // steal the map's horizontal pan. Only Explore-in-map-mode disables it, so
  // Stats↔History stay swipeable.
  const [swipeEnabled, setSwipeEnabled] = useState(true);

  return (
    <View className="flex-1">
      <AppBackground />
      <SetTabSwipeEnabledContext.Provider value={setSwipeEnabled}>
        <MaterialTopTabs
          tabBarPosition="bottom"
          tabBar={(props) => <GlassTabBar {...props} />}
          style={{ backgroundColor: "transparent" }}
          screenOptions={{
            swipeEnabled,
            sceneStyle: { backgroundColor: "transparent" },
          }}
        >
          <MaterialTopTabs.Screen
            name="index"
            options={{
              title: "Explore",
              tabBarIcon: ({ color }: { color: string }) => (
                <Ionicons name="beer" size={22} color={color} />
              ),
            }}
          />
          <MaterialTopTabs.Screen
            name="stats"
            options={{
              title: "Stats",
              tabBarIcon: ({ color }: { color: string }) => (
                <Ionicons name="stats-chart" size={22} color={color} />
              ),
            }}
          />
          <MaterialTopTabs.Screen
            name="history"
            options={{
              title: "History",
              tabBarIcon: ({ color }: { color: string }) => (
                <Ionicons name="time" size={22} color={color} />
              ),
            }}
          />
        </MaterialTopTabs>
      </SetTabSwipeEnabledContext.Provider>
    </View>
  );
}
