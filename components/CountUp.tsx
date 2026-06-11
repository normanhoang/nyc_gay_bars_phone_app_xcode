import { useEffect, useRef, useState } from "react";
import { Text } from "react-native";

type Props = {
  value: number;
  className?: string;
  /** Animation length in ms (default 600). */
  duration?: number;
};

/**
 * Animates from the currently-shown number to `value` with an ease-out, so a
 * fresh mount counts up from zero (e.g. on tab focus via a `key`) while a live
 * increment ticks smoothly from where it was rather than restarting at zero.
 * Drives a few headline numbers, so the per-frame re-render is cheap.
 */
export default function CountUp({ value, className, duration = 600 }: Props) {
  const [display, setDisplay] = useState(0);
  const displayRef = useRef(0);
  displayRef.current = display;

  useEffect(() => {
    const from = displayRef.current;
    if (from === value) return;
    let raf = 0;
    const start = Date.now();
    const tick = () => {
      const t = Math.min(1, (Date.now() - start) / duration);
      const eased = 1 - (1 - t) * (1 - t);
      setDisplay(Math.round(from + (value - from) * eased));
      if (t < 1) raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [value, duration]);

  return <Text className={className}>{display}</Text>;
}
