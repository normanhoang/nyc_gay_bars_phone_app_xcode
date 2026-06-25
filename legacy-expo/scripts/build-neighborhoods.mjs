// One-off build script: NYC neighborhood outlines → lib/neighborhoods.ts
//
// For each neighborhood present in lib/bars.ts we bake a single polygon ring:
//   - Manhattan neighborhoods → the real boundary from a public NYC GeoJSON
//     (matched by name/synonym, largest matching feature wins, then simplified).
//   - Brooklyn & Queens → the convex hull of THEIR bars (the bars are a small
//     cluster, e.g. Astoria — the whole borough would look absurd).
//   - Any name we can't match (or if every remote source fails) → padded convex
//     hull of that neighborhood's bars, so every neighborhood always gets a ring.
//
// Output is committed and read at runtime — the app stays static/offline.
// Re-run with `node scripts/build-neighborhoods.mjs` if bars.ts changes.

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");

// Boroughs whose bars are a small cluster — never use the real borough shape.
const HULL_ONLY = new Set(["Brooklyn", "Queens"]);

// Name → substrings to look for in a GeoJSON feature's neighborhood name.
// (NYC NTA 2020 names are composite, e.g. "Chelsea-Hudson Yards", so we match
// by substring and then disambiguate by which piece actually contains our bars.)
const SYNONYMS = {
  "Hell's Kitchen": ["hell's kitchen", "hells kitchen"],
  Chelsea: ["chelsea"],
  "East Village": ["east village"],
  "West Village": ["west village"],
  "Lower East Side": ["lower east side"],
  "Upper East Side": ["upper east side"],
  "Upper West Side": ["upper west side"],
  Harlem: ["harlem"],
  "Midtown East": ["east midtown", "turtle bay", "midtown east", "midtown"],
};

// Public NYC neighborhood GeoJSON sources, tried in order.
// Primary: NYC Open Data "2020 Neighborhood Tabulation Areas" (official, stable).
const SOURCES = [
  "https://data.cityofnewyork.us/resource/9nt8-h7nd.geojson?$limit=1000",
];

const MAX_POINTS = 80; // simplify rings to at most this many vertices

function readBars() {
  const ts = readFileSync(join(ROOT, "lib", "bars.ts"), "utf8");
  const m = ts.match(/export const BARS:\s*Bar\[\]\s*=\s*(\[[\s\S]*?\]);/);
  if (!m) throw new Error("Could not find BARS array in lib/bars.ts");
  return JSON.parse(m[1]);
}

function featureName(props = {}) {
  return (
    props.neighborhood ??
    props.name ??
    props.ntaname ??
    props.NTAName ??
    props.nta_name ??
    ""
  );
}

async function fetchGeoJSON() {
  for (const url of SOURCES) {
    try {
      const res = await fetch(url, {
        headers: { "User-Agent": "nyc-gaybar-tracker/1.0 (build-time)" },
        signal: AbortSignal.timeout(30000),
      });
      if (!res.ok) continue;
      const data = await res.json();
      if (Array.isArray(data?.features) && data.features.length) {
        console.log(`Fetched ${data.features.length} features from ${url}`);
        return data.features;
      }
    } catch (e) {
      console.warn(`  source failed: ${url} (${e.message})`);
    }
  }
  return null;
}

// ---- geometry helpers (work in [lng, lat] space) ----

function ringArea(ring) {
  let a = 0;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    a += ring[j][0] * ring[i][1] - ring[i][0] * ring[j][1];
  }
  return Math.abs(a) / 2;
}

// Largest outer ring across a Polygon / MultiPolygon geometry.
function largestRing(geometry) {
  if (!geometry) return null;
  let rings = [];
  if (geometry.type === "Polygon") rings = [geometry.coordinates[0]];
  else if (geometry.type === "MultiPolygon")
    rings = geometry.coordinates.map((poly) => poly[0]);
  else return null;
  let best = null;
  let bestArea = -1;
  for (const r of rings) {
    const area = ringArea(r);
    if (area > bestArea) {
      bestArea = area;
      best = r;
    }
  }
  return best;
}

// Andrew's monotone chain convex hull. pts: [lng, lat][] → hull [lng, lat][].
function convexHull(pts) {
  const p = [...pts].sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  if (p.length < 3) return p;
  const cross = (o, a, b) =>
    (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]);
  const lower = [];
  for (const pt of p) {
    while (
      lower.length >= 2 &&
      cross(lower[lower.length - 2], lower[lower.length - 1], pt) <= 0
    )
      lower.pop();
    lower.push(pt);
  }
  const upper = [];
  for (let i = p.length - 1; i >= 0; i--) {
    const pt = p[i];
    while (
      upper.length >= 2 &&
      cross(upper[upper.length - 2], upper[upper.length - 1], pt) <= 0
    )
      upper.pop();
    upper.push(pt);
  }
  lower.pop();
  upper.pop();
  return lower.concat(upper);
}

// Ray-casting point-in-ring test, in [lng, lat] space.
function pointInRing(pt, ring) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const xi = ring[i][0];
    const yi = ring[i][1];
    const xj = ring[j][0];
    const yj = ring[j][1];
    const intersect =
      yi > pt[1] !== yj > pt[1] &&
      pt[0] < ((xj - xi) * (pt[1] - yi)) / (yj - yi) + xi;
    if (intersect) inside = !inside;
  }
  return inside;
}

function centroid(pts) {
  const n = pts.length;
  const sx = pts.reduce((s, p) => s + p[0], 0) / n;
  const sy = pts.reduce((s, p) => s + p[1], 0) / n;
  return [sx, sy];
}

// Push hull vertices outward from the centroid by `factor` for breathing room.
function padRing(ring, factor = 0.12) {
  const [cx, cy] = centroid(ring);
  return ring.map(([x, y]) => [cx + (x - cx) * (1 + factor), cy + (y - cy) * (1 + factor)]);
}

// Small diamond around a point — for neighborhoods with too few bars to hull.
function diamond([cx, cy], r = 0.004) {
  return [
    [cx, cy + r],
    [cx + r, cy],
    [cx, cy - r],
    [cx - r, cy],
  ];
}

// Reduce a ring to <= MAX_POINTS by even decimation (keeps overall shape).
function simplify(ring) {
  if (ring.length <= MAX_POINTS) return ring;
  const step = Math.ceil(ring.length / MAX_POINTS);
  const out = [];
  for (let i = 0; i < ring.length; i += step) out.push(ring[i]);
  return out;
}

function hullForBars(bars) {
  const pts = bars.map((b) => [b.longitude, b.latitude]);
  if (pts.length >= 3) {
    const hull = convexHull(pts);
    if (hull.length >= 3) return padRing(hull);
  }
  return diamond(centroid(pts.length ? pts : [[-73.96, 40.73]]));
}

function toLatLng(ring) {
  return ring.map(([lng, lat]) => ({
    latitude: Number(lat.toFixed(6)),
    longitude: Number(lng.toFixed(6)),
  }));
}

async function main() {
  const bars = readBars();
  const names = [...new Set(bars.map((b) => b.neighborhood))].sort();
  const byHood = new Map();
  for (const b of bars) {
    if (!byHood.has(b.neighborhood)) byHood.set(b.neighborhood, []);
    byHood.get(b.neighborhood).push(b);
  }

  const features = await fetchGeoJSON();
  const polygons = {};
  const sourceUsed = {};

  for (const name of names) {
    const hoodBars = byHood.get(name) ?? [];

    if (!HULL_ONLY.has(name) && features) {
      const syns = SYNONYMS[name] ?? [name.toLowerCase()];
      const cands = [];
      for (const f of features) {
        const fname = String(featureName(f.properties)).toLowerCase();
        if (!fname || !syns.some((s) => fname.includes(s))) continue;
        const ring = largestRing(f.geometry);
        if (!ring) continue;
        const inside = hoodBars.reduce(
          (n, b) => n + (pointInRing([b.longitude, b.latitude], ring) ? 1 : 0),
          0,
        );
        cands.push({ ring, inside, area: ringArea(ring) });
      }
      if (cands.length) {
        // Prefer the piece containing the most of our bars; tiebreak by area.
        cands.sort((a, b) => b.inside - a.inside || b.area - a.area);
        polygons[name] = toLatLng(simplify(cands[0].ring));
        sourceUsed[name] = `real (${cands[0].inside}/${hoodBars.length} bars)`;
        continue;
      }
    }

    polygons[name] = toLatLng(hullForBars(hoodBars));
    sourceUsed[name] = HULL_ONLY.has(name) ? "hull (borough)" : "hull (fallback)";
  }

  const body = `// Generated by scripts/build-neighborhoods.mjs — do not edit by hand.
// Re-run the script if lib/bars.ts changes. Each neighborhood maps to a single
// polygon ring (array of points) drawn as a tappable outline on the map.

export type LatLng = { latitude: number; longitude: number };

export const NEIGHBORHOOD_POLYGONS: Record<string, LatLng[]> = ${JSON.stringify(
    polygons,
    null,
    2,
  )};
`;

  writeFileSync(join(ROOT, "lib", "neighborhoods.ts"), body);

  console.log("\n=== Summary ===");
  for (const name of names) {
    console.log(
      `  ${name.padEnd(18)} ${sourceUsed[name].padEnd(16)} ${polygons[name].length} pts`,
    );
  }
  console.log(`\nWrote ${names.length} neighborhood polygons to lib/neighborhoods.ts`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
