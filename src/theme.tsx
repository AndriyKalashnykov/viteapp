import React from "react";

export interface Theme {
  foreground: string;
  background: string;
}

export const themes: Record<"light" | "dark", Theme> = {
  light: {
    foreground: "#000000",
    background: "#eeeeee",
  },
  dark: {
    foreground: "#ffffff",
    background: "#222222",
  },
};

export const ThemeContext = React.createContext<Theme>(themes.light);
