//! Launcher settings, persisted as `<app_data>/settings.json`.
//! Small + flat — the launcher only has a handful of preferences.

use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use tauri::Manager;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LauncherSettings {
    /// "dark" | "light" — drives the `data-theme` attribute the Base
    /// kit reads.
    pub theme: String,
    /// Opt into the chromatic accent (Base `data-color="true"`).
    pub accent_color: bool,
    /// Re-probe the catalog for updates on launch.
    pub auto_check_updates: bool,
    /// Launch apps immediately after a successful install.
    pub launch_after_install: bool,
    /// Start MattsSoftware itself when the user logs in (macOS
    /// Login Item). Mirrors the actual System Events state — the
    /// frontend calls `set_open_at_login` to apply it.
    #[serde(default)]
    pub open_at_login: bool,
}

impl Default for LauncherSettings {
    fn default() -> Self {
        LauncherSettings {
            theme: "dark".into(),
            accent_color: false,
            auto_check_updates: true,
            launch_after_install: false,
            open_at_login: false,
        }
    }
}

fn settings_path(app: &tauri::AppHandle) -> anyhow::Result<PathBuf> {
    let dir = app
        .path()
        .app_data_dir()
        .map_err(|e| anyhow::anyhow!("app_data_dir: {e}"))?;
    fs::create_dir_all(&dir)?;
    Ok(dir.join("settings.json"))
}

#[tauri::command]
pub fn load_settings(app: tauri::AppHandle) -> LauncherSettings {
    settings_path(&app)
        .ok()
        .filter(|p| p.exists())
        .and_then(|p| fs::read_to_string(p).ok())
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_default()
}

#[tauri::command]
pub fn save_settings(
    app: tauri::AppHandle,
    settings: LauncherSettings,
) -> Result<(), String> {
    let path = settings_path(&app).map_err(|e| e.to_string())?;
    let json = serde_json::to_vec_pretty(&settings).map_err(|e| e.to_string())?;
    fs::write(&path, json).map_err(|e| e.to_string())?;
    Ok(())
}

/// Resolve the MattsSoftware `.app` bundle path. From the running
/// binary we walk ancestors for the `…/MattsSoftware.app` wrapper
/// (`…/MattsSoftware.app/Contents/MacOS/<bin>`). In `tauri dev`
/// there's no bundle, so fall back to the conventional install
/// location — toggling the Login Item is only meaningful for a
/// packaged install anyway.
fn app_bundle_path() -> std::path::PathBuf {
    if let Ok(exe) = std::env::current_exe() {
        for anc in exe.ancestors() {
            if anc.extension().and_then(|e| e.to_str()) == Some("app") {
                return anc.to_path_buf();
            }
        }
    }
    std::path::PathBuf::from("/Applications/MattsSoftware.app")
}

/// Add / remove MattsSoftware as a macOS Login Item via System
/// Events (no extra entitlement needed; the user authorises the
/// automation prompt the first time). Idempotent: we always delete
/// any existing entry first so enabling twice doesn't duplicate it.
#[tauri::command]
pub async fn set_open_at_login(enabled: bool) -> Result<(), String> {
    let bundle = app_bundle_path();
    let path = bundle.to_string_lossy().to_string();
    // Always clear an existing entry first (ignore "not found").
    let _ = std::process::Command::new("osascript")
        .args([
            "-e",
            "tell application \"System Events\" to delete login item \"MattsSoftware\"",
        ])
        .output();
    if enabled {
        let script = format!(
            "tell application \"System Events\" to make login item at end \
             with properties {{path:\"{path}\", hidden:false}}"
        );
        let out = std::process::Command::new("osascript")
            .args(["-e", &script])
            .output()
            .map_err(|e| format!("could not set login item: {e}"))?;
        if !out.status.success() {
            return Err(format!(
                "could not set login item: {}",
                String::from_utf8_lossy(&out.stderr)
            ));
        }
    }
    Ok(())
}
