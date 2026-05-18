import React from "react";
import ReactDOM from "react-dom/client";
// Base design-system tokens FIRST (before any app/theme CSS) — every
// primitive + our own chrome reads these custom properties. Do not
// @import this from a downstream CSS file; import order is
// load-bearing (see the Base consumption notes).
import "@mattmattmattmatt/base/site/styles/tokens.css";
import "./App.css";
import App from "./App";

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
);
