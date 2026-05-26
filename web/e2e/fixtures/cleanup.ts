import type { Page } from "@playwright/test";

const API_BASE =
  process.env.NEXT_PUBLIC_API_BASE_URL ||
  process.env.E2E_API_BASE ||
  "https://api-staging.moproshop.com";

/** Clear all cart items for an authenticated user (reads auth cookie from page context). */
export async function clearCart(page: Page): Promise<void> {
  const cookies = await page.context().cookies();
  const session = cookies.find((c) => c.name === "mopro_s");
  if (!session) return;

  // The httpOnly JWT is in a separate cookie the browser holds automatically.
  // We can do a fetch inside the page context to piggyback on the session.
  await page.evaluate(async (apiBase) => {
    const cartRes = await fetch(`${apiBase}/cart`, { credentials: "include" });
    if (!cartRes.ok) return;
    const { items = [] } = (await cartRes.json()) as { items: Array<{ variant_id: string }> };
    await Promise.all(
      items.map((item) =>
        fetch(`${apiBase}/cart/items/${item.variant_id}`, {
          method: "DELETE",
          credentials: "include",
        }),
      ),
    );
  }, API_BASE);
}

/** Release any open reservation for the authenticated user. */
export async function releaseReservation(
  page: Page,
  reservationId: string,
): Promise<void> {
  await page.evaluate(
    async ({ apiBase, rid }) => {
      await fetch(`${apiBase}/cart/release`, {
        method: "POST",
        credentials: "include",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ reservation_id: rid }),
      });
    },
    { apiBase: API_BASE, rid: reservationId },
  );
}
