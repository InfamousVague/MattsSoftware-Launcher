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
}

impl Default for LauncherSettings {
    fn default() -> Self {
        LauncherSettings {
            theme: "dark".into(),
            accent_color: false,
            auto_check_updates: true,
            launch_after_install: false,
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
