import {
  useCallback,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import {
  getInitialTheme,
  THEME_STORAGE_KEY,
  ThemeContext,
  type ThemeContextValue,
  type ThemeName,
} from "./theme";

/**
 * Provides the active theme and reflects it onto `<html data-theme>`, which
 * drives the CSS custom properties in index.css. Styling stays
 * className/variable-based (never inline `style`), so the strict CSP
 * (`style-src 'self'`, no `unsafe-inline`) holds. The choice is persisted to
 * localStorage so it survives reloads.
 */
export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setThemeState] = useState<ThemeName>(getInitialTheme);

  useEffect(() => {
    document.documentElement.setAttribute("data-theme", theme);
    try {
      window.localStorage.setItem(THEME_STORAGE_KEY, theme);
    } catch {
      /* ignore persistence failures */
    }
  }, [theme]);

  const setTheme = useCallback((next: ThemeName) => setThemeState(next), []);
  const toggleTheme = useCallback(
    () => setThemeState((prev) => (prev === "dark" ? "light" : "dark")),
    [],
  );

  const value = useMemo<ThemeContextValue>(
    () => ({ theme, toggleTheme, setTheme }),
    [theme, toggleTheme, setTheme],
  );

  return (
    <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>
  );
}
