import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  getInitialTheme,
  THEME_STORAGE_KEY,
  ThemeContext,
  useTheme,
} from "./theme";
import { ThemeProvider } from "./ThemeProvider";

function ThemeProbe() {
  const { theme, toggleTheme, setTheme } = useTheme();
  return (
    <div>
      <span data-testid="active">{theme}</span>
      <button onClick={toggleTheme}>toggle</button>
      <button onClick={() => setTheme("dark")}>force-dark</button>
      <button onClick={() => setTheme("light")}>force-light</button>
    </div>
  );
}

describe("ThemeContext / ThemeProvider", () => {
  beforeEach(() => {
    window.localStorage.clear();
    document.documentElement.removeAttribute("data-theme");
  });
  afterEach(() => {
    document.documentElement.removeAttribute("data-theme");
  });

  it("defaults to the light theme outside any provider", () => {
    render(
      <ThemeContext.Consumer>
        {({ theme }) => <span data-testid="active">{theme}</span>}
      </ThemeContext.Consumer>,
    );
    expect(screen.getByTestId("active")).toHaveTextContent("light");
  });

  it("reflects the active theme onto <html data-theme> and persists it", () => {
    render(
      <ThemeProvider>
        <ThemeProbe />
      </ThemeProvider>,
    );
    expect(screen.getByTestId("active")).toHaveTextContent("light");
    expect(document.documentElement.getAttribute("data-theme")).toBe("light");
    expect(window.localStorage.getItem(THEME_STORAGE_KEY)).toBe("light");
  });

  it("toggles between light and dark and updates data-theme + storage", async () => {
    const user = userEvent.setup();
    render(
      <ThemeProvider>
        <ThemeProbe />
      </ThemeProvider>,
    );

    await user.click(screen.getByRole("button", { name: "toggle" }));
    expect(screen.getByTestId("active")).toHaveTextContent("dark");
    expect(document.documentElement.getAttribute("data-theme")).toBe("dark");
    expect(window.localStorage.getItem(THEME_STORAGE_KEY)).toBe("dark");

    await user.click(screen.getByRole("button", { name: "toggle" }));
    expect(screen.getByTestId("active")).toHaveTextContent("light");
    expect(document.documentElement.getAttribute("data-theme")).toBe("light");
  });

  it("setTheme applies a specific theme", async () => {
    const user = userEvent.setup();
    render(
      <ThemeProvider>
        <ThemeProbe />
      </ThemeProvider>,
    );
    await user.click(screen.getByRole("button", { name: "force-dark" }));
    expect(screen.getByTestId("active")).toHaveTextContent("dark");
    await user.click(screen.getByRole("button", { name: "force-light" }));
    expect(screen.getByTestId("active")).toHaveTextContent("light");
  });

  it("restores an explicitly stored choice on mount", () => {
    window.localStorage.setItem(THEME_STORAGE_KEY, "dark");
    render(
      <ThemeProvider>
        <ThemeProbe />
      </ThemeProvider>,
    );
    expect(screen.getByTestId("active")).toHaveTextContent("dark");
    expect(document.documentElement.getAttribute("data-theme")).toBe("dark");
  });

  describe("getInitialTheme", () => {
    it("honors a stored choice", () => {
      window.localStorage.setItem(THEME_STORAGE_KEY, "dark");
      expect(getInitialTheme()).toBe("dark");
    });

    it("falls back to light when nothing is stored (jsdom has no matchMedia)", () => {
      window.localStorage.removeItem(THEME_STORAGE_KEY);
      expect(getInitialTheme()).toBe("light");
    });

    it("ignores an invalid stored value", () => {
      window.localStorage.setItem(THEME_STORAGE_KEY, "purple");
      expect(getInitialTheme()).toBe("light");
    });
  });
});
