import { Ionicons } from "@expo/vector-icons";
import { Text, View } from "react-native";

type Props = {
  note: string | null;
  /** Layout-only spacing classes from the call site (margins etc.). */
  className?: string;
};

/**
 * Brief "10001 → Chelsea" confirmation rendered under a search box after a
 * ZIP code search resolves (state comes from lib/useZipQuery).
 */
export default function ZipNote({ note, className = "" }: Props) {
  if (!note) return null;
  return (
    <View className={`flex-row items-center px-1 ${className}`}>
      <Ionicons name="location" size={13} color="#c084fc" />
      <Text className="ml-1 text-xs font-semibold text-primary">{note}</Text>
    </View>
  );
}
