/// Owns catalog status + the install/open/uninstall action loop.
///
/// `statuses` is the per-app result of the backend probe (installed?
/// version? update available?). `progress` is the live install phase
/// for any app currently being installed/updated, fed by the
/// `launcher://progress` event stream. Components read these two maps
/// and call `install` / `open` / `uninstall` / `refresh`.

import { useCallback, useEffect, useRef, useState } from "react";
import { CATALOG, toAppRef, type CatalogApp } from "../data/catalog";
import {
  fetchStatuses,
  installApp,
  onInstallProgress,
  openApp,
  openExternal,
  uninstallApp,
  type AppStatus,
  type InstallProgress,
} from "../lib/tauri";

type StatusMap = Record<string, AppStatus>;
type ProgressMap = Record<string, InstallProgress | undefined>;

export interface CatalogStatus {
  loading: boolean;
  /// Set when the whole probe failed (not per-app — that's on the
  /// AppStatus.error field).
  probeError: string | null;
  statuses: StatusMap;
  progress: ProgressMap;
  refresh: () => Promise<void>;
  install: (app: CatalogApp) => Promise<void>;
  open: (app: CatalogApp) => Promise<void>;
  uninstall: (app: CatalogApp) => Promise<void>;
}

export function useCatalogStatus(): CatalogStatus {
  const [loading, setLoading] = useState(true);
  const [probeError, setProbeError] = useState<string | null>(null);
  const [statuses, setStatuses] = useState<StatusMap>({});
  const [progress, setProgress] = useState<ProgressMap>({});
  // Avoid overlapping refreshes stomping each other.
  const refreshing = useRef(false);

  const refresh = useCallback(async () => {
    if (refreshing.current) return;
    refreshing.current = true;
    setProbeError(null);
    try {
      const refs = CATALOG.map(toAppRef);
      const list = await fetchStatuses(refs);
      const map: StatusMap = {};
      for (const s of list) map[s.id] = s;
      setStatuses(map);
    } catch (e) {
      setProbeError(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
      refreshing.current = false;
    }
  }, []);

  // Initial probe + subscribe to install progress for its lifetime.
  useEffect(() => {
    void refresh();
    let unlisten: (() => void) | undefined;
    void onInstallProgress((p) => {
      setProgress((prev) => ({ ...prev, [p.id]: p }));
      // On a terminal phase, clear the progress entry shortly after
      // and re-probe so the button flips to its resolved state.
      if (p.phase === "done" || p.phase === "error") {
        window.setTimeout(() => {
          setProgress((prev) => {
            const next = { ...prev };
            delete next[p.id];
            return next;
          });
          if (p.phase === "done") void refresh();
        }, 900);
      }
    }).then((fn) => {
      unlisten = fn;
    });
    return () => unlisten?.();
  }, [refresh]);

  const install = useCallback(
    async (app: CatalogApp) => {
      // Non-installable channels just open their listing/source.
      if (app.channel === "appstore" || app.channel === "library") {
        if (app.url) await openExternal(app.url);
        return;
      }
      const status = statuses[app.id];
      const url = status?.download_url;
      if (!url) {
        setProgress((p) => ({
          ...p,
          [app.id]: {
            id: app.id,
            phase: "error",
            message:
              status?.error ?? "No download is available for this app yet.",
          },
        }));
        return;
      }
      setProgress((p) => ({
        ...p,
        [app.id]: { id: app.id, phase: "download", message: "Starting…" },
      }));
      try {
        await installApp(app.id, url);
        // Success path: the progress event stream drives the rest +
        // triggers a refresh on the terminal "done" phase.
      } catch (e) {
        setProgress((p) => ({
          ...p,
          [app.id]: {
            id: app.id,
            phase: "error",
            message: e instanceof Error ? e.message : String(e),
          },
        }));
      }
    },
    [statuses],
  );

  const open = useCallback(
    async (app: CatalogApp) => {
      if (!app.bundleName) {
        if (app.url) await openExternal(app.url);
        return;
      }
      await openApp(app.bundleName);
    },
    [],
  );

  const uninstall = useCallback(
    async (app: CatalogApp) => {
      if (!app.bundleName) return;
      await uninstallApp(app.bundleName);
      await refresh();
    },
    [refresh],
  );

  return {
    loading,
    probeError,
    statuses,
    progress,
    refresh,
    install,
    open,
    uninstall,
  };
}
