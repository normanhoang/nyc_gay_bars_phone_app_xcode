/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  presets: [require("nativewind/preset")],
  theme: {
    extend: {
      colors: {
        // Pride-accent palette used across the app.
        primary: {
          DEFAULT: "#e0218a", // magenta
          dark: "#b81873",
        },
        ink: {
          DEFAULT: "#0b0b12", // near-black background
          soft: "#16161f",
          card: "#1e1e2a",
        },
        // Translucent "glass" fills layered over the gradient backdrop. Use
        // these (not solid ink-card) on frosted surfaces so the blur shows.
        glass: {
          DEFAULT: "rgba(255,255,255,0.06)",
          strong: "rgba(255,255,255,0.12)",
          line: "rgba(255,255,255,0.12)", // hairline edge highlight
        },
      },
    },
  },
  plugins: [],
};
