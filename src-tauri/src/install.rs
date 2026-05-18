//! Install / update / open actions.
//!
//! macOS DMG install flow (Github + Dmg channels):
//!   1. download the `.dmg` to a temp file
//!   2. `hdiutil attach -nobrowse -noverify` → a mountpoint
//!   3. find the `.app` bundle inside, `ditto` it into /Applications
//!      (replacing any existing copy)
//!   4. `hdiutil detach` the mountpoint (always, even on failure)
//!
//! Each phase emits a `launcher://progress` event so the UI can show
//! a live "Downloading → Mounting → Copying → Done" state instead of
//! a dead spinner. App Store + library channels don't install — the
//! frontend opens their URL via the opener plugin.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;

use serde::Serialize;
use tauri::{AppHandle, Emitter};

#[derive(Debug, Clone, Serialize)]
struct Progress {
    id: String,
    /// "download" | "mount" | "copy" | "cleanup" | "done" | "error"
    phase: String,
    message: String,
}

fn emit(app: &AppHandle, id: &str, phase: &str, message: &str) {
    let _ = app.emit(
        "launcher://progress",
        Progress {
            id: id.to_string(),
            phase: phase.to_string(),
            message: message.to_string(),
        },
    );
}

/// Download `url` into a fresh temp `.dmg`. Blocking client — the
/// whole install runs inside `spawn_blocking`.
fn download_dmg(id: &str, url: &str) -> anyhow::Result<PathBuf> {
    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(300))
        .build()?;
    let resp = client
        .get(url)
        .header("User-Agent", "MattsSoftware-Launcher")
        .send()?;
    if !resp.status().is_success() {
        anyhow::bail!("download failed: HTTP {}", resp.status());
    }
    let bytes = resp.bytes()?;
    let mut path = std::env::temp_dir();
    path.push(format!("mattssoftware-{id}-{}.dmg", std::process::id()));
    let mut f = std::fs::File::create(&path)?;
    f.write_all(&bytes)?;
    Ok(path)
}

/// `hdiutil attach` → the mountpoint path. `-nobrowse` keeps it out
/// of Finder; `-noverify` skips the slow checksum (the bytes came
/// from a TLS download already).
fn attach(dmg: &Path) -> anyhow::Result<PathBuf> {
    let out = Command::new("hdiutil")
        .args(["attach", "-nobrowse", "-noverify", "-quiet"])
        .arg(dmg)
        .arg("-mountrandom")
        .arg("/tmp")
        .output()?;
    if !out.status.success() {
        anyhow::bail!(
            "hdiutil attach failed: {}",
            String::from_utf8_lossy(&out.stderr)
        );
    }
    // The last whitespace-separated token of the last line is the
    // mountpoint (`/tmp/dmg.XXXX  Apple_HFS  /tmp/dmg.XXXX/Volumes/…`).
    let stdout = String::from_utf8_lossy(&out.stdout);
    let mount = stdout
        .lines()
        .filter_map(|l| l.split('\t').last())
        .map(str::trim)
        .filter(|s| s.starts_with('/'))
        .last()
        .map(PathBuf::from)
        .ok_or_else(|| anyhow::anyhow!("could not parse hdiutil mountpoint"))?;
    Ok(mount)
}

fn detach(mount: &Path) {
    let _ = Command::new("hdiutil")
        .args(["detach", "-quiet", "-force"])
        .arg(mount)
        .output();
}

/// First `*.app` directory at the top level of `dir`.
fn find_app_bundle(dir: &Path) -> anyhow::Result<PathBuf> {
    for entry in std::fs::read_dir(dir)? {
        let p = entry?.path();
        if p.extension().and_then(|e| e.to_str()) == Some("app") && p.is_dir() {
            return Ok(p);
        }
    }
    anyhow::bail!("no .app bundle found in the disk image")
}

/// Copy `src` app bundle into /Applications, replacing any existing
/// install. `ditto` preserves bundle metadata + code signature
/// (plain `cp -R` can mangle extended attributes / signing).
fn install_bundle(src: &Path) -> anyhow::Result<PathBuf> {
    let name = src
        .file_name()
        .ok_or_else(|| anyhow::anyhow!("bundle has no name"))?;
    let dest = PathBuf::from("/Applications").join(name);
    if dest.exists() {
        std::fs::remove_dir_all(&dest)?;
    }
    let out = Command::new("ditto").arg(src).arg(&dest).output()?;
    if !out.status.success() {
        anyhow::bail!(
            "copy into /Applications failed: {}",
            String::from_utf8_lossy(&out.stderr)
        );
    }
    Ok(dest)
}

/// Download + mount + copy + cleanup. Returns the installed path.
#[tauri::command]
pub async fn install_app(
    app: AppHandle,
    id: String,
    download_url: String,
) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || {
        emit(&app, &id, "download", "Downloading…");
        let dmg = download_dmg(&id, &download_url).map_err(|e| {
            emit(&app, &id, "error", &e.to_string());
            e.to_string()
        })?;

        emit(&app, &id, "mount", "Mounting disk image…");
        let mount = match attach(&dmg) {
            Ok(m) => m,
            Err(e) => {
                let _ = std::fs::remove_file(&dmg);
                emit(&app, &id, "error", &e.to_string());
                return Err(e.to_string());
            }
        };

        // From here, ALWAYS detach + delete the dmg before returning.
        let result = (|| {
            emit(&app, &id, "copy", "Copying into Applications…");
            let bundle = find_app_bundle(&mount)?;
            let dest = install_bundle(&bundle)?;
            Ok::<String, anyhow::Error>(dest.to_string_lossy().into_owned())
        })();

        emit(&app, &id, "cleanup", "Cleaning up…");
        detach(&mount);
        let _ = std::fs::remove_file(&dmg);

        match result {
            Ok(path) => {
                emit(&app, &id, "done", "Installed");
                Ok(path)
            }
            Err(e) => {
                emit(&app, &id, "error", &e.to_string());
                Err(e.to_string())
            }
        }
    })
    .await
    .map_err(|e| format!("install task join error: {e}"))?
}

/// Launch an installed app by bundle name (no `.app` suffix).
#[tauri::command]
pub async fn open_app(bundle_name: String) -> Result<(), String> {
    let path = format!("/Applications/{bundle_name}.app");
    if !Path::new(&path).exists() {
        return Err(format!("{bundle_name} isn't installed"));
    }
    Command::new("open")
        .arg(&path)
        .status()
        .map_err(|e| format!("failed to launch: {e}"))?;
    Ok(())
}

/// Reveal an installed app in Finder.
#[tauri::command]
pub async fn reveal_app(bundle_name: String) -> Result<(), String> {
    let path = format!("/Applications/{bundle_name}.app");
    if !Path::new(&path).exists() {
        return Err(format!("{bundle_name} isn't installed"));
    }
    Command::new("open")
        .args(["-R"])
        .arg(&path)
        .status()
        .map_err(|e| format!("failed to reveal: {e}"))?;
    Ok(())
}

/// Uninstall = move the bundle to the user's Trash via Finder (so
/// it's recoverable) rather than an irreversible `rm -rf`.
#[tauri::command]
pub async fn uninstall_app(bundle_name: String) -> Result<(), String> {
    let path = format!("/Applications/{bundle_name}.app");
    if !Path::new(&path).exists() {
        return Err(format!("{bundle_name} isn't installed"));
    }
    // AppleScript "delete" sends to Trash (needs no extra
    // entitlement for /Applications when the user authorises).
    let script = format!(
        "tell application \"Finder\" to delete POSIX file \"{path}\""
    );
    let out = Command::new("osascript")
        .args(["-e", &script])
        .output()
        .map_err(|e| format!("uninstall failed to run: {e}"))?;
    if !out.status.success() {
        return Err(format!(
            "uninstall failed: {}",
            String::from_utf8_lossy(&out.stderr)
        ));
    }
    Ok(())
}
