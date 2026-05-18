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

export interface UseCatalogOptions {
  /// Fired once per install when the backend reports the terminal
  /// "done" phase. App uses this to honour the "launch after
  /// install" setting. Kept in a ref internally so changing the
  /// callback never re-subscribes the event listener.
  onInstalled?: (id: string) => void;
}

export function useCatalogStatus(
  opts: UseCatalogOptions = {},
): CatalogStatus {
  const [loading, setLoading] = useState(true);
  const [probeError, setProbeError] = useState<string | null>(null);
  const [statuses, setStatuses] = useState<StatusMap>({});
  const [progress, setProgress] = useState<ProgressMap>({});
  // Avoid overlapping refreshes stomping each other.
  const refreshing = useRef(false);
  // Stable handle to the latest onInstalled so the progress
  // subscription (mounted once) always calls the current closure.
  const onInstalledRef = useRef(opts.onInstalled);
  onInstalledRef.current = opts.onInstalled;
  // Serialise installs. The Rust side runs `hdiutil attach` +
  // `ditto` per app; two of those racing (e.g. "Update all", or an
  // impatient user clicking several Install buttons) can collide on
  // mountpoints / Applications writes. Every install is appended to
  // this promise chain so they run strictly one-at-a-time, FIFO.
  // `queueDepth` tracks how many are waiting so a queued app shows
  // "Queued…" until it reaches the front.
  const queueRef = useRef<Promise<void>>(Promise.resolve());
  const queueDepthRef = useRef(0);

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
        if (p.phase === "done") onInstalledRef.current?.(p.id);
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
      // Anything already in the chain? Then we're queued behind it.
      const waiting = queueDepthRef.current > 0;
      queueDepthRef.current += 1;
      setProgress((p) => ({
        ...p,
        [app.id]: {
          id: app.id,
          phase: "download",
          message: waiting ? "Queued…" : "Starting…",
        },
      }));
      // Append to the FIFO chain: await the prior tail, then run
      // our install; store the new tail so the next caller waits on
      // us too. The stored tail always resolves (errors are
      // swallowed for chain purposes and surfaced per-app via the
      // progress map) so one failure can't wedge the queue.
      const run = async () => {
        // We just reached the front — flip "Queued…" → "Starting…".
        setProgress((p) =>
          p[app.id]?.message === "Queued…"
            ? {
                ...p,
                [app.id]: {
                  id: app.id,
                  phase: "download",
                  message: "Starting…",
                },
              }
            : p,
        );
        try {
          await installApp(app.id, url);
        } catch (e) {
          setProgress((p) => ({
            ...p,
            [app.id]: {
              id: app.id,
              phase: "error",
              message: e instanceof Error ? e.message : String(e),
            },
          }));
        } finally {
          queueDepthRef.current -= 1;
        }
      };
      const mine = queueRef.current.then(run, run);
      queueRef.current = mine;
      await mine;
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
