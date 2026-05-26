/**
 * Spec 02 — Auth (OTP Login)
 * Manual-handoff.md §2 checks: 2.1–2.5
 */
import { test, expect } from "@playwright/test";
import { PHONE, OTP } from "./fixtures/staging-data";

test.describe("Auth — OTP Login", () => {
  test.beforeEach(async ({ page }) => {
    // Start each test logged out
    await page.context().clearCookies();
    await page.goto("/login");
    await page.waitForSelector("#phone");
  });

  test("2.1 — phone entry shows OTP step", async ({ page }) => {
    await page.locator("#phone").fill(PHONE);
    await page.getByRole("button", { name: /Doğrulama Kodu Gönder/i }).click();

    // OTP input must appear — confirms "Kod Gönderildi" equivalent
    await expect(page.locator("#otp")).toBeVisible({ timeout: 10_000 });
  });

  test("2.2 — correct OTP lands on home as authenticated user", async ({ page }) => {
    await page.locator("#phone").fill(PHONE);
    await page.getByRole("button", { name: /Doğrulama Kodu Gönder/i }).click();
    await page.waitForSelector("#otp");
    await page.locator("#otp").fill(OTP);
    await page.getByRole("button", { name: /Doğrula/i }).click();

    // Must leave /login
    await page.waitForURL((url) => !url.pathname.includes("/login"), {
      timeout: 10_000,
    });

    // Confirm session cookie present (mopro_s indicator)
    const cookies = await page.context().cookies();
    const hasSession = cookies.some((c) => c.name === "mopro_s");
    expect(hasSession).toBe(true);
  });

  test("2.3 — wrong OTP shows error, does not log in", async ({ page }) => {
    await page.locator("#phone").fill(PHONE);
    await page.getByRole("button", { name: /Doğrulama Kodu Gönder/i }).click();
    await page.waitForSelector("#otp");
    await page.locator("#otp").fill("000000");
    await page.getByRole("button", { name: /Doğrula/i }).click();

    // Should show a Turkish error message
    const alert = page.getByRole("alert");
    await expect(alert).toBeVisible({ timeout: 5000 });
    await expect(alert).toContainText(/hata|geçersiz|yanlış|invalid/i);

    // Still on /login
    expect(page.url()).toContain("/login");
  });

  test("2.4 — logout clears session and redirects to login", async ({ page }) => {
    // Login first
    await page.locator("#phone").fill(PHONE);
    await page.getByRole("button", { name: /Doğrulama Kodu Gönder/i }).click();
    await page.waitForSelector("#otp");
    await page.locator("#otp").fill(OTP);
    await page.getByRole("button", { name: /Doğrula/i }).click();
    await page.waitForURL((url) => !url.pathname.includes("/login"), {
      timeout: 10_000,
    });

    // Find and click logout
    const logoutBtn = page
      .getByRole("button", { name: /çıkış|logout|sign out/i })
      .or(page.getByRole("link", { name: /çıkış|logout/i }))
      .first();
    await expect(logoutBtn).toBeVisible({ timeout: 5000 });
    await logoutBtn.click();

    // Must redirect to /login or root (unauthenticated)
    await page.waitForURL((url) => url.pathname.includes("/login") || url.pathname === "/", {
      timeout: 10_000,
    });

    // Session cookie cleared
    const cookies = await page.context().cookies();
    const hasSession = cookies.some((c) => c.name === "mopro_s");
    expect(hasSession).toBe(false);
  });

  test("2.5 — re-login with same phone works", async ({ page }) => {
    // Login → logout → login again
    await page.locator("#phone").fill(PHONE);
    await page.getByRole("button", { name: /Doğrulama Kodu Gönder/i }).click();
    await page.waitForSelector("#otp");
    await page.locator("#otp").fill(OTP);
    await page.getByRole("button", { name: /Doğrula/i }).click();
    await page.waitForURL((url) => !url.pathname.includes("/login"), {
      timeout: 10_000,
    });

    await page.context().clearCookies();
    await page.goto("/login");
    await page.waitForSelector("#phone");

    await page.locator("#phone").fill(PHONE);
    await page.getByRole("button", { name: /Doğrulama Kodu Gönder/i }).click();
    await page.waitForSelector("#otp");
    await page.locator("#otp").fill(OTP);
    await page.getByRole("button", { name: /Doğrula/i }).click();
    await page.waitForURL((url) => !url.pathname.includes("/login"), {
      timeout: 10_000,
    });

    const cookies = await page.context().cookies();
    expect(cookies.some((c) => c.name === "mopro_s")).toBe(true);
  });
});
