import { useEffect, useState } from "react";
import { neighborhoodForZip } from "./geo";

/**
 * Search-box state with NYC ZIP interception: typing a recognized ZIP code
 * fires `onZip` with the nearest bar neighborhood (instead of running a
 * fruitless text search for the digits), clears the field, and surfaces a
 * transient "10001 → Chelsea" note for the screen to render (see ZipNote).
 * `onZip` should run the screen's normal neighborhood-selection path.
 */
export function useZipQuery(onZip: (neighborhood: string) => void) {
  const [query, setQuery] = useState("");
  const [zipNote, setZipNote] = useState<string | null>(null);

  const onChangeQuery = (text: string) => {
    const trimmed = text.trim();
    const hood = neighborhoodForZip(trimmed);
    if (hood) {
      onZip(hood);
      // After onZip so this note survives any clearing the handler does.
      setQuery("");
      setZipNote(`${trimmed} → ${hood}`);
      return;
    }
    setQuery(text);
    setZipNote(null);
  };

  // Auto-dismiss the ZIP confirmation after a few seconds. Changing zipNote
  // re-runs the effect, so the cleanup cancels any still-pending timer.
  useEffect(() => {
    if (!zipNote) return;
    const t = setTimeout(() => setZipNote(null), 3500);
    return () => clearTimeout(t);
  }, [zipNote]);

  return { query, setQuery, zipNote, setZipNote, onChangeQuery };
}
