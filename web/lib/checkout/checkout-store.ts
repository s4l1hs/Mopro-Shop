"use client";

import { create } from "zustand";

// Card data is display-only — stored here for the review step summary.
// Full card number and CVV are never stored; they live in react-hook-form
// state in StepPayment and are never sent to our backend (SAQ-A compliance).
interface CardDisplay {
  holderName: string;
  lastFour: string;
  expiryMonth: string;
  expiryYear: string;
}

interface CheckoutState {
  reservationId: string | null;
  idempotencyKey: string | null;
  cardDisplay: CardDisplay;

  setReservationId: (id: string) => void;
  getOrCreateIdempotencyKey: () => string;
  setCardDisplay: (d: CardDisplay) => void;
  clearCardData: () => void;
  reset: () => void;
}

const emptyCard: CardDisplay = {
  holderName: "",
  lastFour: "",
  expiryMonth: "",
  expiryYear: "",
};

export const useCheckoutStore = create<CheckoutState>()((set, get) => ({
  reservationId: null,
  idempotencyKey: null,
  cardDisplay: emptyCard,

  setReservationId: (id) => set({ reservationId: id }),

  getOrCreateIdempotencyKey: () => {
    const existing = get().idempotencyKey;
    if (existing) return existing;
    const key = crypto.randomUUID();
    set({ idempotencyKey: key });
    return key;
  },

  setCardDisplay: (d) => set({ cardDisplay: d }),

  clearCardData: () =>
    set({ cardDisplay: emptyCard }),

  reset: () =>
    set({ reservationId: null, idempotencyKey: null, cardDisplay: emptyCard }),
}));
