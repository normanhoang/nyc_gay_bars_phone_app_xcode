// One-off build script: geocode gay_bars.csv → lib/bars.ts
//
// Strategy per address: US Census geocoder → Nominatim (OSM) → neighborhood
// centroid. Coordinates are baked into lib/bars.ts so the app stays fully
// static/offline at runtime. Re-run with `node scripts/geocode-bars.mjs`
// whenever gay_bars.csv changes.

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, "..");

// Approximate neighborhood centroids — final fallback so every bar gets a pin.
const CENTROIDS = {
  "Hell's Kitchen": [40.7625, -73.9911],
  Chelsea: [40.7465, -74.0014],
  "West Village": [40.7339, -74.0036],
  "East Village": [40.7265, -73.9815],
  "Lower East Side": [40.7155, -73.9843],
  Midtown: [40.7549, -73.984],
  "Flatiron District": [40.7401, -73.9903],
  Meatpacking: [40.7405, -74.0083],
  "Upper East Side": [40.7736, -73.9566],
  "Upper West Side": [40.787, -73.9754],
  "Midtown East": [40.7506, -73.9723],
  Harlem: [40.8116, -73.9465],
  Brooklyn: [40.7045, -73.9335],
  Queens: [40.7466, -73.8916],
};

// Map a neighborhood to the city/borough term geocoders understand.
function cityHint(neighborhood) {
  if (neighborhood === "Brooklyn") return "Brooklyn";
  if (neighborhood === "Queens" || neighborhood === "Astoria") return "Queens";
  return "New York";
}

// Split one CSV line into fields, honoring double-quoted fields with commas.
function splitCsvLine(line) {
  const fields = [];
  let cur = "";
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') inQuotes = !inQuotes;
    else if (ch === "," && !inQuotes) {
      fields.push(cur);
      cur = "";
    } else cur += ch;
  }
  fields.push(cur);
  return fields.map((f) => f.trim());
}

function parseCsv(text) {
  const rows = [];
  const lines = text.split(/\r?\n/).filter((l) => l.trim().length > 0);
  for (let i = 1; i < lines.length; i++) {
    // name,neighborhood,address,tags — address may be quoted; tags are
    // semicolon-separated.
    const [name, neighborhood, address, tags] = splitCsvLine(lines[i]);
    if (!name) continue;
    rows.push({
      name,
      neighborhood,
      address: address ?? "",
      tags: (tags ?? "")
        .split(";")
        .map((t) => t.trim())
        .filter(Boolean),
    });
  }
  return rows;
}

// Coordinates already baked into lib/bars.ts, keyed by bar name — reused so
// re-running this script (e.g. after a tags-only CSV change) needs no network.
function loadCoordCache() {
  const cache = new Map();
  try {
    const ts = readFileSync(join(ROOT, "lib", "bars.ts"), "utf8");
    const m = ts.match(/export const BARS:\s*Bar\[\]\s*=\s*(\[[\s\S]*?\]);/);
    if (m) {
      for (const bar of JSON.parse(m[1])) {
        cache.set(bar.name, { lat: bar.latitude, lon: bar.longitude });
      }
    }
  } catch {
    /* no existing file — geocode everything */
  }
  return cache;
}

function buildQuery(row) {
  let addr = row.address;
  // If the address has no city portion, append the borough hint.
  if (!/,/.test(addr)) addr = `${addr}, ${cityHint(row.neighborhood)}`;
  return `${addr}, NY`;
}

async function geocodeCensus(query) {
  const url =
    "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress" +
    `?address=${encodeURIComponent(query)}` +
    "&benchmark=Public_AR_Current&format=json";
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(20000) });
    if (!res.ok) return null;
    const data = await res.json();
    const m = data?.result?.addressMatches;
    if (m && m.length) {
      return { lat: m[0].coordinates.y, lon: m[0].coordinates.x };
    }
  } catch {
    /* fall through */
  }
  return null;
}

async function geocodeNominatim(query) {
  const url =
    "https://nominatim.openstreetmap.org/search" +
    `?q=${encodeURIComponent(query)}&format=json&limit=1&countrycodes=us`;
  try {
    const res = await fetch(url, {
      headers: { "User-Agent": "nyc-gaybar-tracker/1.0 (build-time geocode)" },
      signal: AbortSignal.timeout(20000),
    });
    if (!res.ok) return null;
    const data = await res.json();
    if (Array.isArray(data) && data.length) {
      return { lat: parseFloat(data[0].lat), lon: parseFloat(data[0].lon) };
    }
  } catch {
    /* fall through */
  }
  return null;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function slugify(name, used) {
  let base = name
    .toLowerCase()
    .replace(/['’.]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  if (!base) base = "bar";
  let id = base;
  let n = 2;
  while (used.has(id)) id = `${base}-${n++}`;
  used.add(id);
  return id;
}

async function main() {
  const csv = readFileSync(join(ROOT, "gay_bars.csv"), "utf8");
  const rows = parseCsv(csv);
  console.log(`Parsed ${rows.length} bars from gay_bars.csv`);

  const coordCache = loadCoordCache();
  const used = new Set();
  const bars = [];
  const tiers = { cached: 0, census: 0, nominatim: 0, centroid: 0 };
  const centroidNames = [];

  for (const row of rows) {
    let coord = coordCache.get(row.name);
    let tier = "cached";

    if (!coord) {
      const query = buildQuery(row);
      coord = await geocodeCensus(query);
      tier = "census";

      if (!coord) {
        await sleep(1100); // be polite to Nominatim (≈1 req/sec)
        coord = await geocodeNominatim(query);
        tier = "nominatim";
      }
      if (!coord) {
        const c = CENTROIDS[row.neighborhood] ?? CENTROIDS["Hell's Kitchen"];
        coord = { lat: c[0], lon: c[1] };
        tier = "centroid";
        centroidNames.push(`${row.name} (${row.neighborhood})`);
      }
    }

    tiers[tier]++;
    bars.push({
      id: slugify(row.name, used),
      name: row.name,
      neighborhood: row.neighborhood,
      address: row.address,
      latitude: Number(coord.lat.toFixed(6)),
      longitude: Number(coord.lon.toFixed(6)),
      ...(row.tags.length ? { tags: row.tags } : {}),
    });
    console.log(
      `  [${tier.padEnd(9)}] ${row.name} → ${coord.lat.toFixed(5)}, ${coord.lon.toFixed(5)}`,
    );
  }

  const neighborhoods = [...new Set(bars.map((b) => b.neighborhood))].sort();

  const fileBody = `import type { Bar } from "./types";

/**
 * NYC gay bars. Generated from gay_bars.csv by scripts/geocode-bars.mjs —
 * do not edit by hand; edit the CSV and re-run the script. Coordinates are
 * geocoded at build time (US Census → Nominatim → neighborhood centroid) so
 * the app needs no map API key or network access at runtime.
 */
export const BARS: Bar[] = ${JSON.stringify(bars, null, 2)};

/** Unique neighborhoods present in BARS, sorted — drives the filter UI. */
export const NEIGHBORHOODS: string[] = ${JSON.stringify(neighborhoods)};

/** Map region that comfortably frames all NYC bars above. */
export const NYC_REGION = {
  latitude: 40.73,
  longitude: -73.96,
  latitudeDelta: 0.22,
  longitudeDelta: 0.22,
};

export function getBarById(id: string): Bar | undefined {
  return BARS.find((bar) => bar.id === id);
}
`;

  writeFileSync(join(ROOT, "lib", "bars.ts"), fileBody);

  console.log("\n=== Summary ===");
  console.log(`Cached:    ${tiers.cached}`);
  console.log(`Census:    ${tiers.census}`);
  console.log(`Nominatim: ${tiers.nominatim}`);
  console.log(`Centroid:  ${tiers.centroid}`);
  if (centroidNames.length) {
    console.log("Fell back to centroid:");
    for (const n of centroidNames) console.log(`  - ${n}`);
  }
  console.log(`\nWrote ${bars.length} bars to lib/bars.ts`);
  console.log(`Neighborhoods (${neighborhoods.length}): ${neighborhoods.join(", ")}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
