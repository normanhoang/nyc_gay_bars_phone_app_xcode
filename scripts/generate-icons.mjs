// Render the SVG icon sources into the PNGs app.json points at.
// Re-run with `node scripts/generate-icons.mjs` after editing the SVGs.

import sharp from "sharp";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ASSETS = join(dirname(fileURLToPath(import.meta.url)), "..", "assets");

const jobs = [
  // [source, output, size] — icon/favicon keep the solid background;
  // adaptive + splash use the transparent foreground variant.
  ["icon.svg", "icon.png", 1024],
  ["icon.svg", "favicon.png", 48],
  ["icon-foreground.svg", "adaptive-icon.png", 1024],
  ["icon-foreground.svg", "splash-icon.png", 1024],
];

for (const [src, out, size] of jobs) {
  await sharp(join(ASSETS, src), { density: 300 })
    .resize(size, size)
    .png()
    .toFile(join(ASSETS, out));
  console.log(`  ${src} → ${out} (${size}×${size})`);
}
console.log("Done.");
