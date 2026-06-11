import { createContext, useContext } from "react";

/**
 * Lets the Explore screen toggle the tab pager's horizontal swipe — it's
 * turned off while the map is showing (the map needs horizontal panning) and
 * on in list view. Provided by the tabs layout, consumed via the hook below.
 */
export const SetTabSwipeEnabledContext = createContext<(enabled: boolean) => void>(
  () => {},
);

export function useSetTabSwipeEnabled() {
  return useContext(SetTabSwipeEnabledContext);
}
