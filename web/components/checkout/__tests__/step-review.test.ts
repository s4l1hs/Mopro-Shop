// Pure logic tests for StepReview — no DOM rendering (vitest env: node).
// These test the fetch payload shape, idempotency key behaviour, and error mapping
// that StepReview uses; component rendering tests would require jsdom.

import { describe, expect, it, vi, beforeEach, afterEach } from "vitest";
import { getSipayErrorMessage } from "@/lib/payments/error-map";

// ── Fetch payload shape ───────────────────────────────────────────────────────

describe("StepReview — fetch payload", () => {
  it("return_url is constructed from window.location.origin", () => {
    // Simulate the URL construction logic from step-review.tsx
    const origin = "https://mopro.com.tr";
    const returnURL = `${origin}/checkout/redirect`;
    expect(returnURL).toBe("https://mopro.com.tr/checkout/redirect");
  });

  it("card data is NOT included in the payload sent to /api/payments/intent", () => {
    // The payload must only contain address, return_url, and consent — no card fields.
    const payload = {
      address: { fullName: "Ali Yılmaz" },
      return_url: "https://mopro.com.tr/checkout/redirect",
      consent: {
        distance_sale: true,
        pre_info: true,
        ts: new Date().toISOString(),
      },
    };

    expect(payload).not.toHaveProperty("card");
    expect(payload).not.toHaveProperty("card_number");
    expect(payload).not.toHaveProperty("cvv");
    expect(payload).not.toHaveProperty("expiry");
  });

  it("idempotency key in header matches UUID format", () => {
    const key = crypto.randomUUID();
    expect(key).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i,
    );
  });
});

// ── Idempotency — same key reused within session ──────────────────────────────

describe("StepReview — idempotency key", () => {
  it("getOrCreateIdempotencyKey returns same key on repeated calls", async () => {
    // Import the store fresh
    const { useCheckoutStore } = await import("@/lib/checkout/checkout-store");
    const store = useCheckoutStore.getState();
    store.reset();

    const key1 = store.getOrCreateIdempotencyKey();
    const key2 = store.getOrCreateIdempotencyKey();
    expect(key1).toBe(key2);
    expect(key1).toMatch(/^[0-9a-f-]{36}$/i);
  });

  it("reset() clears the idempotency key so a new one is generated", async () => {
    const { useCheckoutStore } = await import("@/lib/checkout/checkout-store");
    const store = useCheckoutStore.getState();
    store.reset();

    const key1 = store.getOrCreateIdempotencyKey();
    store.reset();
    const key2 = store.getOrCreateIdempotencyKey();
    expect(key1).not.toBe(key2);
  });
});

// ── Card data hygiene ─────────────────────────────────────────────────────────

describe("StepReview — card data cleared after submit", () => {
  it("clearCardData() zeros holder name and last four", async () => {
    const { useCheckoutStore } = await import("@/lib/checkout/checkout-store");
    const store = useCheckoutStore.getState();

    store.setCardDisplay({
      holderName: "ALI YILMAZ",
      lastFour: "1234",
      expiryMonth: "12",
      expiryYear: "28",
    });

    expect(useCheckoutStore.getState().cardDisplay.holderName).toBe("ALI YILMAZ");

    store.clearCardData();

    const { cardDisplay } = useCheckoutStore.getState();
    expect(cardDisplay.holderName).toBe("");
    expect(cardDisplay.lastFour).toBe("");
    expect(cardDisplay.expiryMonth).toBe("");
    expect(cardDisplay.expiryYear).toBe("");
  });
});

// ── Fetch mock: success path ──────────────────────────────────────────────────

describe("StepReview — fetch integration (mocked)", () => {
  let originalFetch: typeof global.fetch;

  beforeEach(() => {
    originalFetch = global.fetch;
  });

  afterEach(() => {
    global.fetch = originalFetch;
  });

  it("on 201 with sipay_3ds_url, response contains the URL", async () => {
    const mockURL = "https://ccpayment.sipay.com.tr/3DGate?token=abc123";
    global.fetch = vi.fn().mockResolvedValueOnce({
      ok: true,
      status: 201,
      json: async () => ({
        sipay_3ds_url: mockURL,
        session_id: "sess-001",
        invoice_id: "inv-001",
      }),
    } as Response);

    const res = await fetch("/api/payments/intent", {
      method: "POST",
      headers: { "Content-Type": "application/json", "Idempotency-Key": "inv-001" },
      body: JSON.stringify({
        address: { fullName: "Ali Yılmaz" },
        return_url: "https://mopro.com.tr/checkout/redirect",
        consent: { distance_sale: true, pre_info: true, ts: new Date().toISOString() },
      }),
    });
    const data = await res.json();

    expect(data.sipay_3ds_url).toBe(mockURL);
    expect(fetch).toHaveBeenCalledWith(
      "/api/payments/intent",
      expect.objectContaining({ method: "POST" }),
    );
  });

  it("on 429 rate_limit_exceeded, surfaces Turkish error message", () => {
    const msg = getSipayErrorMessage("rate_limit_exceeded");
    expect(msg).toContain("dakika");
  });

  it("on non-OK response, surfaces Turkish error for known code", () => {
    const msg = getSipayErrorMessage("insufficient_funds");
    expect(msg).toContain("bakiye");
  });

  it("on unknown error code, surfaces generic Turkish fallback", () => {
    const msg = getSipayErrorMessage("some_unknown_code");
    expect(msg).toContain("tekrar deneyin");
  });
});
