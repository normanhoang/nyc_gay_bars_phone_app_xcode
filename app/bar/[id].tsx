import { useLocalSearchParams, useRouter } from "expo-router";
import BarDetailSheet from "../../components/BarDetailSheet";

// Thin modal wrapper around BarDetailSheet, opened from Explore (logs today).
// The backdated flow doesn't come through here — log/[day] renders the sheet
// in-place inside its own modal (see that file).
export default function BarDetailScreen() {
  const { id, day } = useLocalSearchParams<{ id: string; day?: string }>();
  const router = useRouter();
  return (
    <BarDetailSheet barId={id ?? ""} day={day} onClose={() => router.back()} />
  );
}
