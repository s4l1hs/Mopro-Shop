import { defineConfig, devices, type ReporterDescription } from "@playwright/test";

const baseURL = process.env.E2E_BASE_URL || "http://localhost:3000";
const isCI = !!process.env.CI;

const reporter: ReporterDescription[] = [
  ["html", { outputFolder: "playwright-report" }],
  ["list"],
];

const projects = [
  { name: "chromium", use: { ...devices["Desktop Chrome"] } },
  { name: "firefox", use: { ...devices["Desktop Firefox"] } },
  { name: "webkit", use: { ...devices["Desktop Safari"] } },
  { name: "mobile-chrome", use: { ...devices["Pixel 5"] } },
];

const sharedConfig = {
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: isCI,
  retries: isCI ? 1 : 0,
  workers: isCI ? 2 : 4,
  reporter,
  use: {
    baseURL,
    trace: "on-first-retry" as const,
    screenshot: "only-on-failure" as const,
  },
  projects,
};

// When E2E_BASE_URL is set, point at a live staging/production URL — no local server needed.
// When it is not set, spin up Next.js dev server automatically with staging API.
export default process.env.E2E_BASE_URL
  ? defineConfig(sharedConfig)
  : defineConfig({
      ...sharedConfig,
      webServer: {
        command: "pnpm dev",
        url: "http://localhost:3000",
        reuseExistingServer: !isCI,
        timeout: 120_000,
        env: {
          NEXT_PUBLIC_API_BASE_URL: "https://api-staging.moproshop.com",
        },
      },
    });
