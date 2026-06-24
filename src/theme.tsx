import { createContext, useContext } from "react";

export type ThemeName = "light" | "dark";

export interface ThemeContextValue {
  /** The active theme. */
  theme: ThemeName;
  /** Switch to the other theme. */
  toggleTheme: () => void;
  /** Apply a specific theme. */
  setTheme: (theme: ThemeName) => void;
}

/** localStorage key holding the user's explicit theme choice. */
export const THEME_STORAGE_KEY = "viteapp-theme";

const noop = () => {};

export const ThemeContext = createContext<ThemeContextValue>({
  theme: "light",
  toggleTheme: noop,
  setTheme: noop,
});

/**
 * Resolve the initial theme: an explicit stored choice wins; otherwise follow
 * the OS `prefers-color-scheme`. Guarded for non-DOM / test environments where
 * `window` or `matchMedia` may be absent (jsdom does not implement matchMedia).
 */
export function getInitialTheme(): ThemeName {
  if (typeof window === "undefined") return "light";
  try {
    const stored = window.localStorage.getItem(THEME_STORAGE_KEY);
    if (stored === "light" || stored === "dark") return stored;
  } catch {
    /* localStorage may be unavailable (private mode / sandboxed iframe) */
  }
  return window.matchMedia?.("(prefers-color-scheme: dark)")?.matches
    ? "dark"
    : "light";
}

/** Access the active theme and its setters. */
export function useTheme(): ThemeContextValue {
  return useContext(ThemeContext);
}
