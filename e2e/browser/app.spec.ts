import { test, expect } from "@playwright/test";

const STORAGE_KEY = "viteapp-theme";

// These run against the BUILT bundle served by the production nginx container
// (started by `make e2e-browser`), so they exercise what jsdom + curl cannot:
// the real Rolldown/terser output executing in a browser, under the production
// CSP that nginx emits.

test.describe("viteapp built bundle", () => {
  test("boots and the counter increments", async ({ page }) => {
    await page.goto("/");
    await expect(
      page.getByRole("heading", { name: "Vite + React" }),
    ).toBeVisible();

    const counter = page.getByRole("button", { name: /count is 0/i });
    await expect(counter).toBeVisible();
    await counter.click();
    await expect(
      page.getByRole("button", { name: /count is 1/i }),
    ).toBeVisible();
  });

  test("theme toggle flips data-theme, button label, and persists across reload", async ({
    page,
  }) => {
    await page.goto("/");
    const html = page.locator("html");
    const toggle = page.getByTestId("theme-toggle");

    await expect(html).toHaveAttribute("data-theme", /^(light|dark)$/);
    const initial = await html.getAttribute("data-theme");
    const flipped = initial === "dark" ? "light" : "dark";
    await expect(toggle).toHaveText(
      initial === "dark" ? /Light mode/ : /Dark mode/,
    );

    await toggle.click();
    await expect(html).toHaveAttribute("data-theme", flipped);
    await expect(toggle).toHaveText(
      flipped === "dark" ? /Light mode/ : /Dark mode/,
    );

    // The choice is persisted and survives a full reload.
    await page.reload();
    await expect(html).toHaveAttribute("data-theme", flipped);
    expect(
      await page.evaluate((k) => localStorage.getItem(k), STORAGE_KEY),
    ).toBe(flipped);
  });

  test("no CSP violations or uncaught errors on load + toggle", async ({
    page,
  }) => {
    // The theme is applied via `data-theme` + CSS variables (no inline styles),
    // so the strict CSP nginx serves (`style-src 'self'`, no `unsafe-inline`)
    // must not fire. A regression that reintroduced inline styles would surface
    // here as a "Refused to apply inline style" CSP console error.
    const cspViolations: string[] = [];
    const pageErrors: string[] = [];
    page.on("console", (msg) => {
      if (
        msg.type() === "error" &&
        /content security policy|refused to/i.test(msg.text())
      ) {
        cspViolations.push(msg.text());
      }
    });
    page.on("pageerror", (err) => pageErrors.push(String(err)));

    await page.goto("/");
    await page.getByTestId("theme-toggle").click();

    expect(cspViolations, cspViolations.join("\n")).toEqual([]);
    expect(pageErrors, pageErrors.join("\n")).toEqual([]);
  });
});
