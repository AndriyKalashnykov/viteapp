import React from "react";
import ReactDOM from "react-dom/client";
import "./index.css";
import App from "./App";
import reportWebVitals from "./reportWebVitals";
import { ThemeContext, themes } from "./theme";

const root = ReactDOM.createRoot(
  document.getElementById("root") as HTMLElement,
);
root.render(
  <React.StrictMode>
    <ThemeContext.Provider value={themes.dark}>
      <App />
    </ThemeContext.Provider>
  </React.StrictMode>,
);

reportWebVitals(console.log);
