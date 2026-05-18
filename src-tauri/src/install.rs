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
    /// 0-100 during the download phase when the server sent a
    /// Content-Length; None for indeterminate phases (mount/copy)
    /// or when the size is unknown.
    pct: Option<u8>,
}

fn emit(app: &AppHandle, id: &str, phase: &str, message: &str) {
    emit_pct(app, id, phase, message, None);
}

fn emit_pct(
    app: &AppHandle,
    id: &str,
    phase: &str,
    message: &str,
    pct: Option<u8>,
) {
    let _ = app.emit(
        "launcher://progress",
        Progress {
            id: id.to_string(),
            phase: phase.to_string(),
            message: message.to_string(),
            pct,
        },
    );
}

fn human_mb(bytes: u64) -> String {
    format!("{:.1} MB", bytes as f64 / 1_048_576.0)
}

/// Download `url` into a fresh temp `.dmg`, streaming the body and
/// emitting a real byte-percentage as it goes (so the UI shows a
/// moving bar, not a dead spinner). Blocking client + `Read` loop —
/// the whole install runs inside `spawn_blocking`.
fn download_dmg(
    app: &AppHandle,
    id: &str,
    url: &str,
) -> anyhow::Result<PathBuf> {
    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(600))
        .build()?;
    let mut resp = client
        .get(url)
        .header("User-Agent", "MattsSoftware-Launcher")
        .send()?;
    if !resp.status().is_success() {
        anyhow::bail!("download failed: HTTP {}", resp.status());
    }
    let total = resp.content_length();

    let mut path = std::env::temp_dir();
    path.push(format!("mattssoftware-{id}-{}.dmg", std::process::id()));
    let mut f = std::fs::File::create(&path)?;

    let mut buf = [0u8; 64 * 1024];
    let mut downloaded: u64 = 0;
    // Throttle event spam: only emit when the integer percent moves
    // (or, when size is unknown, every ~2 MB).
    let mut last_pct: i32 = -1;
    let mut last_emit_bytes: u64 = 0;
    loop {
        let n = std::io::Read::read(&mut resp, &mut buf)?;
        if n == 0 {
            break;
        }
        f.write_all(&buf[..n])?;
        downloaded += n as u64;
        match total {
            Some(t) if t > 0 => {
                let pct = ((downloaded as f64 / t as f64) * 100.0) as i32;
                if pct != last_pct {
                    last_pct = pct;
                    emit_pct(
                        app,
                        id,
                        "download",
                        &format!(
                            "Downloading… {} / {}",
                            human_mb(downloaded),
                            human_mb(t)
                        ),
                        Some(pct.clamp(0, 100) as u8),
                    );
                }
            }
            _ => {
                if downloaded - last_emit_bytes >= 2 * 1_048_576 {
                    last_emit_bytes = downloaded;
                    emit_pct(
                        app,
                        id,
                        "download",
                        &format!("Downloading… {}", human_mb(downloaded)),
                        None,
                    );
                }
            }
        }
    }
    f.flush()?;
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
        emit(&app, &id, "download", "Starting download…");
        let dmg = download_dmg(&app, &id, &download_url).map_err(|e| {
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
