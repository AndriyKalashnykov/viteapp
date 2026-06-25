import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

// Accessibility scan of the built bundle in BOTH themes. The theme toggle is
// the highest-risk surface for a11y regressions (text/background contrast,
// the toggle button's ARIA), so we scan light AND dark. We fail on
// serious/critical impact only — minor/moderate axe findings on the starter
// scaffold are reported but not gated, to keep the gate signal-to-noise high.
const BLOCKING_IMPACTS = ["serious", "critical"];

async function scan(page: import("@playwright/test").Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"])
    .analyze();
  return results.violations.filter((v) =>
    BLOCKING_IMPACTS.includes(v.impact ?? ""),
  );
}

test.describe("accessibility (axe)", () => {
  // Emulate reduced motion so the app's theme color-transition is disabled
  // (it's gated behind `prefers-reduced-motion: no-preference`). axe then reads
  // the SETTLED palette instead of a mid-animation light/dark blend. Done via the
  // runtime `emulateMedia` call — both a global `use.reducedMotion` and a
  // describe-level `test.use({reducedMotion})` get shadowed by the project's
  // `devices["Desktop Chrome"]` use block, whereas emulateMedia always applies.
  test.beforeEach(async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
  });

  test("no serious/critical violations in light theme", async ({ page }) => {
    await page.goto("/");
    const toggle = page.getByTestId("theme-toggle");
    // Ensure a deterministic starting theme regardless of the runner's OS pref.
    if ((await page.locator("html").getAttribute("data-theme")) === "dark") {
      await toggle.click();
    }
    await expect(page.locator("html")).toHaveAttribute("data-theme", "light");

    const violations = await scan(page);
    expect(
      violations,
      violations.map((v) => `${v.id}: ${v.help}`).join("\n"),
    ).toEqual([]);
  });

  test("no serious/critical violations in dark theme", async ({ page }) => {
    await page.goto("/");
    const toggle = page.getByTestId("theme-toggle");
    if ((await page.locator("html").getAttribute("data-theme")) === "light") {
      await toggle.click();
    }
    await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");

    const violations = await scan(page);
    expect(
      violations,
      violations.map((v) => `${v.id}: ${v.help}`).join("\n"),
    ).toEqual([]);
  });
});
