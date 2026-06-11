import { Pressable, Text } from "react-native";
import Glass from "./Glass";

export type SegmentedOption<T extends string> = {
  value: T;
  label: string;
};

type Props<T extends string> = {
  options: SegmentedOption<T>[];
  value: T;
  onChange: (value: T) => void;
};

export default function SegmentedToggle<T extends string>({
  options,
  value,
  onChange,
}: Props<T>) {
  return (
    <Glass radius={999} bordered className="flex-row p-1">
      {options.map((opt) => {
        const active = opt.value === value;
        return (
          <Pressable
            key={opt.value}
            onPress={() => onChange(opt.value)}
            className={
              active
                ? "flex-1 items-center rounded-full bg-primary py-2"
                : "flex-1 items-center rounded-full py-2"
            }
          >
            <Text
              className={
                active
                  ? "text-sm font-semibold text-white"
                  : "text-sm font-semibold text-gray-200"
              }
            >
              {opt.label}
            </Text>
          </Pressable>
        );
      })}
    </Glass>
  );
}
