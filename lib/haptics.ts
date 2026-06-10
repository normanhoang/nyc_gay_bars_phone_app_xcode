import * as Haptics from "expo-haptics";

// Thin wrappers so callers never await or handle platforms without haptics
// (web rejects; old devices no-op).

/** Light tick for small interactions (logging a drink). */
export function lightTap(): void {
  Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => {});
}

/** Success notification (badge unlocked). */
export function success(): void {
  Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(
    () => {},
  );
}
