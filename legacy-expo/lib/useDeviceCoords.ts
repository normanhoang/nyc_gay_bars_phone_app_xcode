import * as Location from "expo-location";
import { useEffect, useState } from "react";

export type Coords = { lat: number; lng: number };

/**
 * Fetches the device location once on mount (asking for foreground permission
 * if needed). Returns null until it resolves — and forever if permission is
 * denied or the fix fails, so callers fall back to location-free behavior.
 */
export function useDeviceCoords(): Coords | null {
  const [coords, setCoords] = useState<Coords | null>(null);

  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const { status } =
          await Location.requestForegroundPermissionsAsync();
        if (!active || status !== "granted") return;
        const pos = await Location.getCurrentPositionAsync({
          accuracy: Location.Accuracy.Balanced,
        });
        if (!active) return;
        setCoords({ lat: pos.coords.latitude, lng: pos.coords.longitude });
      } catch {
        // Location unavailable — callers keep their location-free fallback.
      }
    })();
    return () => {
      active = false;
    };
  }, []);

  return coords;
}
