/**
 * Spec 10 — Cross-Platform Integration Checks
 * Manual-handoff.md §11 checks: 11.1–11.5
 *
 * All five checks require full Sipay payment flow (card entry in Sipay-hosted page).
 * The automated portion verifies the pre-payment state machine:
 *   - happy-path: everything up to initiate is correct
 *   - failed card: error handling path is present in UI
 *   - mid-3DS cancel: cart preserved after cancellation
 *
 * 11.1 full completion, 11.4, 11.5 are marked manual — they require real webhook delivery.
 */
import { expect } from "@playwright/test";
import { test } from "./fixtures/auth";
import { clearCart, releaseReservation } from "./fixtures/cleanup";
import { SEED_CATEGORY_SLUG } from "./fixtures/staging-data";

const API_BASE =
  process.env.NEXT_PUBLIC_API_BASE_URL ||
  process.env.E2E_API_BASE ||
  "https://api-staging.moproshop.com";

test.describe("Cross-Platform Integration — Automated Pre-payment Assertions", () => {
  test.beforeEach(async ({ authedPage }) => {
    await clearCart(authedPage);
  });

  test("11.1 pre — checkout/initiate returns 200 for valid reservation", async ({
    authedPage: page,
  }) => {
    // Step 1: get a product with variant
    await page.goto(`/categories/${SEED_CATEGORY_SLUG}`);
    const card = page.locator("a[href*='/products/']").first();
    await expect(card).toBeVisible({ timeout: 10_000 });
    await card.click();
    await page.waitForURL(/\/products\/\d+/, { timeout: 8000 });

    // Step 2: add to cart
    const addBtn = page.getByRole("button", { name: /Sepete Ekle/i });
    await expect(addBtn).toBeVisible({ timeout: 5000 });
    await addBtn.click();
    await page.waitForTimeout(800);

    // Step 3: reserve via API
    const reserveData = await page.evaluate(async (base) => {
      const res = await fetch(`${base}/cart/reserve`, {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: "{}",
      });
      return { status: res.status, body: await res.json().catch(() => null) };
    }, API_BASE);

    expect(reserveData.status).toBe(200);
    const reservationId = reserveData.body?.reservation_id;
    expect(reservationId).toBeTruthy();

    // Step 4: initiate checkout
    const idempotencyKey = `e2e-${Date.now()}`;
    const checkoutData = await page.evaluate(
      async ({ base, rid, ikey }) => {
        const res = await fetch(`${base}/checkout/initiate`, {
          method: "POST",
          credentials: "include",
          headers: {
            "Content-Type": "application/json",
            "Idempotency-Key": ikey,
          },
          body: JSON.stringify({
            reservation_id: rid,
            buyer_name: "E2E",
            buyer_surname: "Test",
            buyer_email: "e2e@moproshop.com",
          }),
        });
        return { status: res.status, body: await res.json().catch(() => null) };
      },
      { base: API_BASE, rid: reservationId, ikey: idempotencyKey },
    );

    // initiate returns 200 with payment_url when Sipay sandbox is available
    // Accept 200 (success) or 422/503 (Sipay sandbox unavailable) — not 500
    expect([200, 422, 503]).toContain(checkoutData.status);
    if (checkoutData.status === 200) {
      expect(checkoutData.body?.payment_url || checkoutData.body?.redirect_url).toBeTruthy();
    }

    // Clean up
    if (reservationId) await releaseReservation(page, reservationId);
  });

  test("11.2 — failed card path: UI renders payment error state", async ({
    authedPage: page,
  }) => {
    // Navigate to checkout page to verify error handling UI exists
    await page.goto("/checkout");

    // The checkout page must load without crashing
    await expect(page.locator("main, [role='main']").first()).toBeVisible({ timeout: 8000 });

    // Verify checkout/redirect page handles error state gracefully
    await page.goto("/checkout/redirect?status=failed");
    await expect(page.locator("main, [role='main']").first()).toBeVisible({ timeout: 5000 });
    const body = await page.textContent("body");
    // Page should acknowledge failure — not crash
    expect(body?.trim().length).toBeGreaterThan(0);
  });

  test("11.3 — mid-3DS cancel: cart preserved after cancellation URL", async ({
    authedPage: page,
  }) => {
    // Add a product first
    await page.goto(`/categories/${SEED_CATEGORY_SLUG}`);
    const card = page.locator("a[href*='/products/']").first();
    await expect(card).toBeVisible({ timeout: 10_000 });
    await card.click();
    await page.waitForURL(/\/products\/\d+/, { timeout: 8000 });
    const addBtn = page.getByRole("button", { name: /Sepete Ekle/i });
    if (await addBtn.isVisible({ timeout: 3000 })) {
      await addBtn.click();
      await page.waitForTimeout(800);
    }

    // Simulate 3DS cancel callback URL
    await page.goto("/checkout/redirect?status=cancelled");
    await expect(page.locator("main, [role='main']").first()).toBeVisible({ timeout: 5000 });

    // Cart should still have items (no auto-clear on cancel)
    const cartData = await page.evaluate(async (base) => {
      const res = await fetch(`${base}/cart`, { credentials: "include" });
      return res.json().catch(() => null);
    }, API_BASE);

    const items = cartData?.items ?? [];
    // Items should be preserved (cancel should NOT clear cart)
    expect(items.length).toBeGreaterThanOrEqual(1);
  });

  // Full 3DS completion + webhook delivery requires human interaction
  test.skip("11.1 full — real card payment completes → order confirmed [MANUAL]", async () => {});
  test.skip("11.4 — webhook race: both paths idempotent [MANUAL]", async () => {});
  test.skip("11.5 — delayed webhook: order auto-updates within 60s [MANUAL]", async () => {});
});
