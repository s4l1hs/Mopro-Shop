import { test as base, expect, type Page } from "@playwright/test";
import { PHONE, OTP } from "./staging-data";

/** Log in via OTP and return the page. Re-uses storageState when possible. */
async function loginOtp(page: Page): Promise<void> {
  await page.goto("/login");
  await page.waitForSelector("#phone");

  // Fill phone digits (without +90 prefix — the form prepends it)
  await page.locator("#phone").fill(PHONE);
  await page.getByRole("button", { name: /Doğrulama Kodu Gönder/i }).click();

  // Wait for OTP step
  await page.waitForSelector("#otp");
  await page.locator("#otp").fill(OTP);
  await page.getByRole("button", { name: /Doğrula/i }).click();

  // After login, server may redirect to profile completion or home
  await page.waitForURL((url) => !url.pathname.includes("/login"), { timeout: 10_000 });

  // If redirected to complete-profile, skip it by navigating to home
  if (page.url().includes("/complete-profile")) {
    await page.goto("/");
  }
}

/** Playwright fixture that provides an authenticated page. */
export const test = base.extend<{ authedPage: Page }>({
  authedPage: async ({ page }, use) => {
    await loginOtp(page);
    await use(page);
  },
});

export { expect };
export { loginOtp };
