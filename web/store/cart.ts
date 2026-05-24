"use client";

import { create } from "zustand";
import { persist } from "zustand/middleware";
import { apiFetch } from "@/lib/api-client";
import { cashbackMonthlyMinor } from "@/lib/money";

export interface CartItem {
  productId: number;
  slug?: string;
  title: string;
  brand?: string;
  priceMinor: number;
  currency: string;
  coverImageUrl: string;
  commissionPctBps?: number;
  quantity: number;
}

interface CartState {
  items: CartItem[];
  itemCount: number;
  drawerOpen: boolean;

  addItem: (item: Omit<CartItem, "quantity"> & { quantity?: number }) => void;
  removeItem: (productId: number) => void;
  updateQuantity: (productId: number, quantity: number) => void;
  clearCart: () => void;
  openDrawer: () => void;
  closeDrawer: () => void;
  revalidatePrices: () => Promise<void>;
}

function sumQty(items: CartItem[]): number {
  return items.reduce((n, it) => n + it.quantity, 0);
}

export const useCartStore = create<CartState>()(
  persist(
    (set, get) => ({
      items: [],
      itemCount: 0,
      drawerOpen: false,

      openDrawer: () => set({ drawerOpen: true }),
      closeDrawer: () => set({ drawerOpen: false }),

      addItem: ({ quantity = 1, ...rest }) =>
        set((s) => {
          const existing = s.items.find((it) => it.productId === rest.productId);
          const items = existing
            ? s.items.map((it) =>
                it.productId === rest.productId
                  ? { ...it, quantity: Math.min(10, it.quantity + quantity) }
                  : it,
              )
            : [...s.items, { ...rest, quantity: Math.min(10, quantity) }];
          return { items, itemCount: sumQty(items) };
        }),

      removeItem: (productId) =>
        set((s) => {
          const items = s.items.filter((it) => it.productId !== productId);
          return { items, itemCount: sumQty(items) };
        }),

      updateQuantity: (productId, quantity) =>
        set((s) => {
          const items =
            quantity <= 0
              ? s.items.filter((it) => it.productId !== productId)
              : s.items.map((it) =>
                  it.productId === productId
                    ? { ...it, quantity: Math.min(10, quantity) }
                    : it,
                );
          return { items, itemCount: sumQty(items) };
        }),

      clearCart: () => set({ items: [], itemCount: 0 }),

      revalidatePrices: async () => {
        const { items } = get();
        if (items.length === 0) return;
        try {
          type ValidateResponse = {
            items: Array<{ productId: number; priceMinor: number }>;
          };
          const data = await apiFetch<ValidateResponse>("/cart/validate", {
            method: "POST",
            body: {
              items: items.map((it) => ({
                productId: it.productId,
                quantity: it.quantity,
              })),
            },
          });
          set((s) => {
            const updated = s.items.map((it) => {
              const v = data.items.find((d) => d.productId === it.productId);
              return v ? { ...it, priceMinor: v.priceMinor } : it;
            });
            return { items: updated };
          });
        } catch {
          // silently ignore — stale prices shown, user sees real price at checkout
        }
      },
    }),
    {
      name: "mopro-cart-v1",
      partialize: (s) => ({ items: s.items, itemCount: s.itemCount }),
    },
  ),
);

// Typed selector hooks
export function useCartItems() {
  return useCartStore((s) => s.items);
}

export function useCartCount() {
  return useCartStore((s) => s.itemCount);
}

export function useCartTotals() {
  return useCartStore((s) => {
    const subtotalMinor = s.items.reduce(
      (sum, it) => sum + it.priceMinor * it.quantity,
      0,
    );
    const monthlyCashbackMinor = s.items.reduce((sum, it) => {
      if (!it.commissionPctBps) return sum;
      return (
        sum + cashbackMonthlyMinor(it.priceMinor, it.commissionPctBps) * it.quantity
      );
    }, 0);
    return { subtotalMinor, monthlyCashbackMinor, currency: "TRY" as const };
  });
}
