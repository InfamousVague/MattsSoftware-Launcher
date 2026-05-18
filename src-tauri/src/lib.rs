//! MattsSoftware launcher — Tauri backend.
//!
//! A thin native surface for an Adobe-CC / MacPaw-style launcher:
//! detect which of my apps are installed + at what version
//! (`catalog`), install / update / open / uninstall them
//! (`install`), and persist the handful of launcher preferences
//! (`settings`). Everything heavy (network, hdiutil, ditto) runs on
//! blocking threads so the UI never stalls.

mod catalog;
mod install;
mod settings;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            catalog::app_statuses,
            install::install_app,
            install::open_app,
            install::reveal_app,
            install::uninstall_app,
            settings::load_settings,
            settings::save_settings,
        ])
        .run(tauri::generate_context!())
        .expect("error while running MattsSoftware launcher");
}
