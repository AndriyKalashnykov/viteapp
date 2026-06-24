import { defineConfig, devices } from "@playwright/test";

// The nginx container under test is started by `make e2e-browser` (mirroring
// `make e2e`/`make dast`), so Playwright does NOT manage a webServer — it just
// drives whatever BASE_URL points at. Default matches the Makefile's host port.
const baseURL = process.env.BASE_URL ?? "http://localhost:8080";

export default defineConfig({
  testDir: "./e2e/browser",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: process.env.CI
    ? [["list"], ["html", { open: "never" }]]
    : [["list"]],
  use: {
    baseURL,
    trace: "on-first-retry",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
