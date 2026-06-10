import * as SecureStore from "expo-secure-store";
import { createClient } from "@supabase/supabase-js";

const storage = {
  getItem: (key: string) => SecureStore.getItemAsync(key),
  setItem: (key: string, value: string) => SecureStore.setItemAsync(key, value),
  removeItem: (key: string) => SecureStore.deleteItemAsync(key),
};

export const supabase = createClient(
  "https://ptulzftybirztvdbnfde.supabase.co",
  "sb_publishable_GIDAxNtHiv2wdO1oZe8f6A_u80E-2Mf",
  {
    auth: {
      storage,
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: false,
    },
  },
);
