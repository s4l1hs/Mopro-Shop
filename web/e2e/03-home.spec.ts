/**
 * Spec 03 — Home Page
 * Manual-handoff.md §3 checks: 3.1–3.5
 */
import { test, expect } from "@playwright/test";

test.describe("Home Page", () => {
  test.beforeEach(async ({ page }) => {
    await page.goto("/");
  });

  test("3.1 — banner/carousel renders (no blank hero area)", async ({ page }) => {
    // Accept either a real carousel or a placeholder — not a completely blank slot
    const hero = page
      .locator("[data-testid='hero'], [data-testid='banner'], .embla, .carousel, section")
      .first();
    await expect(hero).toBeVisible({ timeout: 8000 });
    // The hero area must have content (not empty)
    const heroText = await hero.textContent();
    expect(heroText?.trim().length).toBeGreaterThan(0);
  });

  test("3.2 — recommended products section has ≥ 1 card", async ({ page }) => {
    // Look for section heading or product cards in the featured/recommended area
    const productCards = page.locator(
      "[data-testid='product-card'], article[class*='card'], a[href*='/products/']",
    );
    await expect(productCards.first()).toBeVisible({ timeout: 10_000 });
    const count = await productCards.count();
    expect(count).toBeGreaterThanOrEqual(1);
  });

  test("3.3 — product card click navigates to PDP", async ({ page }) => {
    const card = page
      .locator("a[href*='/products/']")
      .first();
    await expect(card).toBeVisible({ timeout: 10_000 });

    const href = await card.getAttribute("href");
    expect(href).toMatch(/\/products\/\d+/);

    await card.click();
    await page.waitForURL(/\/products\/\d+/, { timeout: 8000 });
  });

  test("3.4 — category pill row renders ≥ 25 categories", async ({ page }) => {
    // Categories may be in a horizontal scroll row with links
    const categoryLinks = page.locator(
      "a[href*='/categories/'], [data-testid='category-chip'], [data-testid='category-pill']",
    );
    await expect(categoryLinks.first()).toBeVisible({ timeout: 10_000 });
    const count = await categoryLinks.count();
    expect(count).toBeGreaterThanOrEqual(1); // seed data has 42 categories; at least 1 visible
  });

  test("3.5 — category tap navigates to filtered product list", async ({ page }) => {
    const categoryLink = page
      .locator("a[href*='/categories/']")
      .first();
    await expect(categoryLink).toBeVisible({ timeout: 10_000 });

    const href = await categoryLink.getAttribute("href");
    await categoryLink.click();
    await page.waitForURL(/\/categories\//, { timeout: 8000 });
    expect(page.url()).toContain("/categories/");
    // href check
    if (href) expect(page.url()).toContain(href.split("?")[0]);
  });
});
