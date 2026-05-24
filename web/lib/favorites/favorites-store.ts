"use client";

import { create } from "zustand";
import { persist } from "zustand/middleware";

interface FavoritesState {
  ids: number[];
  toggle: (productId: number) => void;
  has: (productId: number) => boolean;
  clear: () => void;
}

export const useFavoritesStore = create<FavoritesState>()(
  persist(
    (set, get) => ({
      ids: [],

      toggle: (productId) =>
        set((s) => ({
          ids: s.ids.includes(productId)
            ? s.ids.filter((id) => id !== productId)
            : [...s.ids, productId],
        })),

      has: (productId) => get().ids.includes(productId),

      clear: () => set({ ids: [] }),
    }),
    {
      name: "mopro-favorites-v1",
      partialize: (s) => ({ ids: s.ids }),
    },
  ),
);

export function useIsFavorite(productId: number): boolean {
  return useFavoritesStore((s) => s.ids.includes(productId));
}
