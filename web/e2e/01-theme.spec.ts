/**
 * Spec 01 — Cold Load + Theme
 * Manual-handoff.md §1 checks: 1.1, 1.2, 1.3
 * Flutter checks (1.4, 1.5) are manual-only.
 */
import { test, expect } from "@playwright/test";

test.describe("Cold Load + Theme", () => {
  test("1.1 — page loads with no console errors", async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") consoleErrors.push(msg.text());
    });
    page.on("pageerror", (err) => consoleErrors.push(err.message));

    const start = Date.now();
    const response = await page.goto("/");
    const elapsed = Date.now() - start;

    expect(response?.status()).toBe(200);
    expect(elapsed).toBeLessThan(5000); // generous for CI network

    // Filter out known benign Next.js hydration noise in dev mode
    const blocking = consoleErrors.filter(
      (e) =>
        !e.includes("Warning:") &&
        !e.includes("DevTools") &&
        !e.includes("hydrat"),
    );
    expect(blocking).toHaveLength(0);
  });

  test("1.2 — dark/light theme toggle switches theme instantly", async ({ page }) => {
    await page.goto("/");

    // Initial state: read html data-theme or class
    const html = page.locator("html");
    const initialClass = await html.getAttribute("class");
    const initialData = await html.getAttribute("data-theme");
    const initialTheme = initialClass?.includes("dark")
      ? "dark"
      : initialData?.includes("dark")
        ? "dark"
        : "light";

    // Find theme toggle — accepts multiple common test IDs / aria labels
    const toggle = page
      .getByRole("button", { name: /theme|tema|dark|light|karanlık|aydınlık/i })
      .or(page.locator("[data-testid='theme-toggle']"))
      .first();

    await expect(toggle).toBeVisible({ timeout: 5000 });
    await toggle.click();

    // Theme should flip within 500ms
    await page.waitForTimeout(300);
    const newClass = await html.getAttribute("class");
    const newData = await html.getAttribute("data-theme");
    const newTheme = newClass?.includes("dark")
      ? "dark"
      : newData?.includes("dark")
        ? "dark"
        : "light";

    expect(newTheme).not.toBe(initialTheme);
  });

  test("1.3 — hard reload renders correctly (no blank page)", async ({ page }) => {
    await page.goto("/");
    await page.reload({ waitUntil: "domcontentloaded" });

    // Basic structural elements must be present
    await expect(page.locator("body")).not.toBeEmpty();
    await expect(page.locator("header, nav, main").first()).toBeVisible();
  });
});
