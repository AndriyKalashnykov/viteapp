import React from "react";
import { render, screen } from "@testing-library/react";
import { describe, it, expect } from "vitest";
import { ThemeContext, themes } from "./theme";

function ThemeProbe() {
  const theme = React.useContext(ThemeContext);
  return (
    <div data-testid="probe" style={theme}>
      fg={theme.foreground} bg={theme.background}
    </div>
  );
}

describe("ThemeContext", () => {
  it("falls back to the light theme outside a provider", () => {
    render(<ThemeProbe />);
    expect(screen.getByTestId("probe")).toHaveTextContent(
      `fg=${themes.light.foreground} bg=${themes.light.background}`,
    );
  });

  it("delivers the dark theme inside the dark provider", () => {
    render(
      <ThemeContext.Provider value={themes.dark}>
        <ThemeProbe />
      </ThemeContext.Provider>,
    );
    expect(screen.getByTestId("probe")).toHaveTextContent(
      `fg=${themes.dark.foreground} bg=${themes.dark.background}`,
    );
  });

  it("exposes both light and dark palettes", () => {
    expect(themes.light.foreground).toBe("#000000");
    expect(themes.light.background).toBe("#eeeeee");
    expect(themes.dark.foreground).toBe("#ffffff");
    expect(themes.dark.background).toBe("#222222");
  });
});
