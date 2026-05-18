/// Typed wrappers over the Rust command surface + the install
/// progress event. One place so components never touch `invoke`
/// string names directly.

import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import { openUrl } from "@tauri-apps/plugin-opener";
import type { AppRef } from "../data/catalog";

export interface AppStatus {
  id: string;
  installed: boolean;
  installed_version: string | null;
  latest_version: string | null;
  download_url: string | null;
  updatable: boolean;
  release_notes: string | null;
  release_url: string | null;
  error: string | null;
}

export type InstallPhase =
  | "download"
  | "mount"
  | "copy"
  | "cleanup"
  | "done"
  | "error";

export interface InstallProgress {
  id: string;
  phase: InstallPhase;
  message: string;
  /// 0-100 during the download phase when a Content-Length was
  /// known; null/absent for indeterminate phases.
  pct?: number | null;
}

export interface LauncherSettings {
  theme: "dark" | "light";
  accent_color: boolean;
  auto_check_updates: boolean;
  launch_after_install: boolean;
  open_at_login: boolean;
}

export function fetchStatuses(apps: AppRef[]): Promise<AppStatus[]> {
  return invoke<AppStatus[]>("app_statuses", { apps });
}

export function installApp(
  id: string,
  downloadUrl: string,
): Promise<string> {
  return invoke<string>("install_app", { id, downloadUrl });
}

export function openApp(bundleName: string): Promise<void> {
  return invoke("open_app", { bundleName });
}

export function revealApp(bundleName: string): Promise<void> {
  return invoke("reveal_app", { bundleName });
}

export function uninstallApp(bundleName: string): Promise<void> {
  return invoke("uninstall_app", { bundleName });
}

export function loadSettings(): Promise<LauncherSettings> {
  return invoke<LauncherSettings>("load_settings");
}

export function saveSettings(settings: LauncherSettings): Promise<void> {
  return invoke("save_settings", { settings });
}

/// Add/remove MattsSoftware as a macOS Login Item.
export function setOpenAtLogin(enabled: boolean): Promise<void> {
  return invoke("set_open_at_login", { enabled });
}

/// Subscribe to the backend's per-install progress stream. Returns
/// the unlisten fn — call it on unmount.
export function onInstallProgress(
  cb: (p: InstallProgress) => void,
): Promise<UnlistenFn> {
  return listen<InstallProgress>("launcher://progress", (e) =>
    cb(e.payload),
  );
}

/// Open an external URL in the system browser / App Store.
export function openExternal(url: string): Promise<void> {
  return openUrl(url);
}
