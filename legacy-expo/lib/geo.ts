import { BARS, NEIGHBORHOODS } from "./bars";
import type { Bar } from "./types";
import { ZIP_CENTROIDS } from "./zips";

/** Squared equirectangular distance — fine for comparing/ranking, not metric. */
function sqDist(
  lat: number,
  lng: number,
  bar: Bar,
  latRadCos: number,
): number {
  const dLat = bar.latitude - lat;
  const dLon = (bar.longitude - lng) * latRadCos;
  return dLat * dLat + dLon * dLon;
}

const MILES_PER_DEG_LAT = 69.0;

type Bounds = { minLat: number; maxLat: number; minLon: number; maxLon: number };

/** Bounding box of each neighborhood's bars, computed once from BARS. */
const NEIGHBORHOOD_BOUNDS: Record<string, Bounds> = (() => {
  const bounds: Record<string, Bounds> = {};
  for (const bar of BARS) {
    const b = bounds[bar.neighborhood];
    if (!b) {
      bounds[bar.neighborhood] = {
        minLat: bar.latitude,
        maxLat: bar.latitude,
        minLon: bar.longitude,
        maxLon: bar.longitude,
      };
    } else {
      b.minLat = Math.min(b.minLat, bar.latitude);
      b.maxLat = Math.max(b.maxLat, bar.latitude);
      b.minLon = Math.min(b.minLon, bar.longitude);
      b.maxLon = Math.max(b.maxLon, bar.longitude);
    }
  }
  return bounds;
})();

type RegionLike = {
  latitude: number;
  longitude: number;
  latitudeDelta: number;
  longitudeDelta: number;
};

/** How many neighborhoods sit entirely inside the visible map region. */
export function fullyVisibleNeighborhoods(region: RegionLike): number {
  const minLat = region.latitude - region.latitudeDelta / 2;
  const maxLat = region.latitude + region.latitudeDelta / 2;
  const minLon = region.longitude - region.longitudeDelta / 2;
  const maxLon = region.longitude + region.longitudeDelta / 2;
  let count = 0;
  for (const b of Object.values(NEIGHBORHOOD_BOUNDS)) {
    if (
      b.minLat >= minLat &&
      b.maxLat <= maxLat &&
      b.minLon >= minLon &&
      b.maxLon <= maxLon
    ) {
      count++;
    }
  }
  return count;
}

/** Equirectangular distance in miles — accurate enough at city scale. */
export function distanceMiles(lat: number, lng: number, bar: Bar): number {
  const cos = Math.cos((lat * Math.PI) / 180);
  return Math.sqrt(sqDist(lat, lng, bar, cos)) * MILES_PER_DEG_LAT;
}

/** The bar closest to the given coordinates. */
export function nearestBar(latitude: number, longitude: number): Bar {
  const cos = Math.cos((latitude * Math.PI) / 180);
  let best = BARS[0];
  let bestDist = Infinity;
  for (const bar of BARS) {
    const dist = sqDist(latitude, longitude, bar, cos);
    if (dist < bestDist) {
      bestDist = dist;
      best = bar;
    }
  }
  return best;
}

/**
 * Neighborhoods ordered by how close their nearest bar is to the given
 * coordinates (closest first). Used to sort the filter chips by proximity.
 */
export function neighborhoodsByProximity(
  latitude: number,
  longitude: number,
): string[] {
  const cos = Math.cos((latitude * Math.PI) / 180);
  const minDist = new Map<string, number>();
  for (const bar of BARS) {
    const dist = sqDist(latitude, longitude, bar, cos);
    const cur = minDist.get(bar.neighborhood);
    if (cur === undefined || dist < cur) minDist.set(bar.neighborhood, dist);
  }
  return [...NEIGHBORHOODS].sort(
    (a, b) => (minDist.get(a) ?? Infinity) - (minDist.get(b) ?? Infinity),
  );
}

/**
 * True when the string is a 5-digit ZIP code in our NYC dataset. The regex
 * gate also keeps Object.prototype keys ("constructor" etc.) from passing
 * the `in` lookup.
 */
export function isKnownZip(query: string): boolean {
  return /^\d{5}$/.test(query) && query in ZIP_CENTROIDS;
}

/**
 * The bar neighborhood closest to a NYC ZIP code's centroid, or null if the
 * ZIP isn't in our dataset. Used to jump the neighborhood filter to a typed ZIP.
 */
export function neighborhoodForZip(zip: string): string | null {
  if (!isKnownZip(zip)) return null;
  const c = ZIP_CENTROIDS[zip];
  return nearestBar(c.lat, c.lng).neighborhood;
}
