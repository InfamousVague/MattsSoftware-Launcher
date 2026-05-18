/// MattsSoftware — single-page launcher.
///
/// Layout (top → bottom): a draggable frameless title strip with the
/// wordmark + search + refresh + settings; a category filter row;
/// then the responsive app grid. A right slide-over shows one app's
/// detail; settings is a Base Dialog. No router — it's one page.

import { useEffect, useMemo, useState } from "react";
import { Input } from "@base/primitives/input";
import "@base/primitives/input/input.css";
import { Button } from "@base/primitives/button";
import "@base/primitives/button/button.css";
import { Spinner } from "@base/primitives/spinner";
import "@base/primitives/spinner/spinner.css";
import { Icon } from "@base/primitives/icon";
import "@base/primitives/icon/icon.css";
import { search as searchIcon } from "@base/primitives/icon/icons/search";
import { refreshCw } from "@base/primitives/icon/icons/refresh-cw";
import { settings as settingsIcon } from "@base/primitives/icon/icons/settings";
import { boxes } from "@base/primitives/icon/icons/boxes";
import { CATALOG, CATEGORIES, type CatalogApp } from "./data/catalog";
import { useCatalogStatus } from "./hooks/useCatalogStatus";
import {
  loadSettings,
  saveSettings,
  type LauncherSettings,
} from "./lib/tauri";
import { AppCard } from "./components/AppCard";
import { AppDetail } from "./components/AppDetail";
import { SettingsModal } from "./components/SettingsModal";

const DEFAULT_SETTINGS: LauncherSettings = {
  theme: "dark",
  accent_color: false,
  auto_check_updates: true,
  launch_after_install: false,
};

/// Reflect theme + accent onto <html> — the attributes the Base kit
/// reads (`data-theme`, `data-color`).
function applyAppearance(s: LauncherSettings) {
  const el = document.documentElement;
  el.setAttribute("data-theme", s.theme);
  if (s.accent_color) el.setAttribute("data-color", "true");
  else el.removeAttribute("data-color");
}

export default function App() {
  const {
    loading,
    probeError,
    statuses,
    progress,
    refresh,
    install,
    open,
    uninstall,
  } = useCatalogStatus();

  const [query, setQuery] = useState("");
  const [category, setCategory] = useState<string>("All");
  const [selected, setSelected] = useState<CatalogApp | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [settings, setSettings] =
    useState<LauncherSettings>(DEFAULT_SETTINGS);

  // Load persisted settings once; apply appearance immediately so
  // there's no light→dark flash after the default.
  useEffect(() => {
    void loadSettings()
      .then((s) => {
        setSettings(s);
        applyAppearance(s);
      })
      .catch(() => applyAppearance(DEFAULT_SETTINGS));
  }, []);

  const onSettingsChange = (next: LauncherSettings) => {
    setSettings(next);
    applyAppearance(next);
    void saveSettings(next).catch(() => {
      /* non-fatal — preference just won't persist across relaunch */
    });
  };

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    return CATALOG.filter((a) => {
      if (category !== "All" && a.category !== category) return false;
      if (!q) return true;
      return (
        a.name.toLowerCase().includes(q) ||
        a.tagline.toLowerCase().includes(q) ||
        a.description.toLowerCase().includes(q) ||
        a.tags.some((t) => t.toLowerCase().includes(q))
      );
    });
  }, [query, category]);

  const updatableCount = useMemo(
    () =>
      CATALOG.filter((a) => statuses[a.id]?.updatable).length,
    [statuses],
  );

  return (
    <div className="ms-app">
      {/* Frameless drag strip — overlay title bar, traffic lights
          sit at the left so the wordmark is inset past them. */}
      <header className="ms-titlebar" data-tauri-drag-region>
        <div className="ms-brand">
          <span className="ms-brand__mark" aria-hidden>
            <Icon icon={boxes} size="lg" color="currentColor" />
          </span>
          <div className="ms-brand__text">
            <span className="ms-brand__name">MattsSoftware</span>
            <span className="ms-brand__sub">
              {updatableCount > 0
                ? `${updatableCount} update${updatableCount > 1 ? "s" : ""} available`
                : "Every app I've built, in one place"}
            </span>
          </div>
        </div>

        <div className="ms-titlebar__tools">
          <div className="ms-search">
            <Input
              size="sm"
              placeholder="Search apps…"
              iconLeft={searchIcon}
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onClear={() => setQuery("")}
              aria-label="Search apps"
            />
          </div>
          <Button
            variant="ghost"
            size="sm"
            iconOnly
            icon={refreshCw}
            loading={loading}
            onClick={() => void refresh()}
            aria-label="Refresh"
            title="Re-check installed apps + updates"
          />
          <Button
            variant="ghost"
            size="sm"
            iconOnly
            icon={settingsIcon}
            onClick={() => setSettingsOpen(true)}
            aria-label="Settings"
            title="Settings"
          />
        </div>
      </header>

      <nav className="ms-filters" aria-label="Categories">
        {["All", ...CATEGORIES].map((c) => (
          <button
            key={c}
            type="button"
            className={
              "ms-filter" + (category === c ? " ms-filter--active" : "")
            }
            onClick={() => setCategory(c)}
          >
            {c}
          </button>
        ))}
      </nav>

      <main className="ms-main">
        {probeError && (
          <div className="ms-banner" role="status">
            Couldn't check for updates: {probeError}. Showing what's known.
          </div>
        )}

        {loading && Object.keys(statuses).length === 0 ? (
          <div className="ms-empty">
            <Spinner size="md" />
            <p>Checking your apps…</p>
          </div>
        ) : filtered.length === 0 ? (
          <div className="ms-empty">
            <Icon icon={searchIcon} size="xl" color="tertiary" />
            <p>No apps match “{query}”.</p>
          </div>
        ) : (
          <div className="ms-grid">
            {filtered.map((app) => (
              <AppCard
                key={app.id}
                app={app}
                status={statuses[app.id]}
                progress={progress[app.id]}
                onSelect={setSelected}
                onInstall={install}
                onOpen={open}
              />
            ))}
          </div>
        )}
      </main>

      <AppDetail
        app={selected}
        status={selected ? statuses[selected.id] : undefined}
        progress={selected ? progress[selected.id] : undefined}
        onClose={() => setSelected(null)}
        onInstall={install}
        onOpen={open}
        onUninstall={(a) => {
          void uninstall(a);
          setSelected(null);
        }}
      />

      <SettingsModal
        open={settingsOpen}
        settings={settings}
        onClose={() => setSettingsOpen(false)}
        onChange={onSettingsChange}
      />
    </div>
  );
}
