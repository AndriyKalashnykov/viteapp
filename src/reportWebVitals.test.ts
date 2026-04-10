import { describe, it, expect, vi } from "vitest";
import reportWebVitals from "./reportWebVitals";

vi.mock("web-vitals", () => ({
  onCLS: vi.fn(),
  onINP: vi.fn(),
  onFCP: vi.fn(),
  onLCP: vi.fn(),
  onTTFB: vi.fn(),
}));

describe("reportWebVitals", () => {
  it("does nothing when no callback is provided", () => {
    expect(() => reportWebVitals()).not.toThrow();
  });

  it("does nothing when the value is not a function", () => {
    // Runtime guard: the parameter is typed as a function, but we explicitly
    // test the `instanceof Function` branch by passing a non-callable value.
    // @ts-expect-error testing runtime guard against non-function input
    expect(() => reportWebVitals("not a function")).not.toThrow();
  });

  it("registers every web-vitals metric when a callback is provided", async () => {
    const callback = vi.fn();
    reportWebVitals(callback);

    // Wait for the dynamic `import("web-vitals")` to resolve.
    await new Promise((resolve) => setTimeout(resolve, 0));

    const webVitals = await import("web-vitals");
    expect(webVitals.onCLS).toHaveBeenCalledWith(callback);
    expect(webVitals.onINP).toHaveBeenCalledWith(callback);
    expect(webVitals.onFCP).toHaveBeenCalledWith(callback);
    expect(webVitals.onLCP).toHaveBeenCalledWith(callback);
    expect(webVitals.onTTFB).toHaveBeenCalledWith(callback);
  });
});
