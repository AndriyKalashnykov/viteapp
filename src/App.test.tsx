import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, beforeEach, describe, it, expect } from "vitest";
import App from "./App";
import { ThemeProvider } from "./ThemeProvider";

describe("App", () => {
  beforeEach(() => {
    window.localStorage.clear();
    document.documentElement.removeAttribute("data-theme");
  });
  afterEach(() => {
    document.documentElement.removeAttribute("data-theme");
  });

  it("renders headline", () => {
    render(<App />);
    expect(screen.getByText("Vite + React")).toBeInTheDocument();
  });

  it("toggles the theme via the toggle button", async () => {
    const user = userEvent.setup();
    render(
      <ThemeProvider>
        <App />
      </ThemeProvider>,
    );

    const toggle = screen.getByTestId("theme-toggle");
    expect(toggle).toHaveTextContent("Dark mode");
    expect(document.documentElement.getAttribute("data-theme")).toBe("light");

    await user.click(toggle);
    expect(document.documentElement.getAttribute("data-theme")).toBe("dark");
    expect(screen.getByTestId("theme-toggle")).toHaveTextContent("Light mode");
  });

  it("renders logo links", () => {
    render(<App />);
    expect(screen.getByAltText("Vite logo")).toBeInTheDocument();
    expect(screen.getByAltText("React logo")).toBeInTheDocument();
  });

  it("increments counter on click", async () => {
    const user = userEvent.setup();
    render(<App />);

    const button = screen.getByRole("button", { name: /count is 0/i });
    expect(button).toBeInTheDocument();

    await user.click(button);
    expect(
      screen.getByRole("button", { name: /count is 1/i }),
    ).toBeInTheDocument();

    await user.click(button);
    expect(
      screen.getByRole("button", { name: /count is 2/i }),
    ).toBeInTheDocument();
  });
});
