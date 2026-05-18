//! App catalog status: is each catalogued app installed, at what
//! version, and is a newer one available.
//!
//! Detection is macOS-first (the launcher targets macOS): an app is
//! "installed" if `/Applications/<BundleName>.app` exists, and its
//! version is the `CFBundleShortVersionString` from that bundle's
//! Info.plist. We read it with `defaults read` rather than pulling a
//! plist-parsing crate — `defaults` is built into macOS and handles
//! both XML and binary plists transparently.
//!
//! "Latest available" comes from the per-app distribution channel:
//! GitHub Releases (the common case for the desktop apps), the App
//! Store (Tap), or none (Base — it's a library, not an installable).

use std::path::PathBuf;
use std::process::Command;

use serde::{Deserialize, Serialize};

/// Distribution channel for one catalogued app. Mirrors the
/// `channel` discriminant in the frontend catalog (src/data/catalog.ts).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Channel {
    /// Downloaded as a `.dmg` asset off a GitHub release.
    Github,
    /// Mac App Store — we can only deep-link to the listing.
    Appstore,
    /// Direct `.dmg` URL (no release API).
    Dmg,
    /// Not an installable app (e.g. the Base design system library).
    Library,
}

/// One catalog entry as sent from the frontend. Kept intentionally
/// small — the rich presentation metadata stays in the TS catalog;
/// the backend only needs what it takes to detect + fetch.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppRef {
    pub id: String,
    pub name: String,
    /// The `.app` bundle's name in `/Applications` WITHOUT the
    /// `.app` suffix (e.g. "Blip"). None for non-installables.
    pub bundle_name: Option<String>,
    pub channel: Channel,
    /// `owner/repo` (or just `repo` — we default the owner) for the
    /// Github channel.
    pub github_repo: Option<String>,
    /// App Store / direct-DMG URL for the Appstore / Dmg channels.
    pub url: Option<String>,
}

/// Resolved status for one app — what the launcher renders its
/// Install / Update / Open button from.
#[derive(Debug, Clone, Serialize)]
pub struct AppStatus {
    pub id: String,
    pub installed: bool,
    pub installed_version: Option<String>,
    pub latest_version: Option<String>,
    /// Direct download URL when one is known (Github `.dmg` asset or
    /// the Dmg channel's URL). None for App Store / library.
    pub download_url: Option<String>,
    /// True when installed AND a newer version is available.
    pub updatable: bool,
    /// Populated when the status probe itself failed (offline, rate
    /// limited, …) so the UI can show "couldn't check" rather than
    /// silently implying up-to-date.
    pub error: Option<String>,
}

const GITHUB_OWNER: &str = "InfamousVague";

/// `/Applications/<BundleName>.app`. We only look in the system
/// Applications folder — the launcher installs there, and a user
/// app in `~/Applications` is an edge case we intentionally don't
/// claim to manage.
fn app_bundle_path(bundle_name: &str) -> PathBuf {
    PathBuf::from("/Applications").join(format!("{bundle_name}.app"))
}

/// Installed version via `defaults read <bundle>/Contents/Info
/// CFBundleShortVersionString`. Returns None if the app isn't
/// present or the key is missing.
fn installed_version(bundle_name: &str) -> Option<String> {
    let bundle = app_bundle_path(bundle_name);
    if !bundle.exists() {
        return None;
    }
    // `defaults read` wants the plist path WITHOUT the `.plist`
    // extension.
    let info = bundle.join("Contents/Info");
    let out = Command::new("defaults")
        .arg("read")
        .arg(&info)
        .arg("CFBundleShortVersionString")
        .output()
        .ok()?;
    if !out.status.success() {
        // Bundle exists but no short-version key — still "installed",
        // just version-unknown. Signal with an empty string so the
        // caller can distinguish "present, version ?" from "absent".
        return Some(String::new());
    }
    let v = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if v.is_empty() {
        Some(String::new())
    } else {
        Some(v)
    }
}

/// Latest GitHub release: `(tag, first .dmg asset url)`. `repo` may
/// be `owner/name` or bare `name` (owner defaults to InfamousVague).
fn github_latest(repo: &str) -> anyhow::Result<(String, Option<String>)> {
    let full = if repo.contains('/') {
        repo.to_string()
    } else {
        format!("{GITHUB_OWNER}/{repo}")
    };
    let url = format!("https://api.github.com/repos/{full}/releases/latest");
    let client = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(15))
        .build()?;
    // GitHub's API rejects requests with no User-Agent.
    let resp = client
        .get(&url)
        .header("User-Agent", "MattsSoftware-Launcher")
        .header("Accept", "application/vnd.github+json")
        .send()?;
    if !resp.status().is_success() {
        anyhow::bail!("GitHub API {} for {full}", resp.status());
    }
    let json: serde_json::Value = resp.json()?;
    let tag = json
        .get("tag_name")
        .and_then(|v| v.as_str())
        .unwrap_or_default()
        .to_string();
    let dmg = json
        .get("assets")
        .and_then(|a| a.as_array())
        .and_then(|assets| {
            assets.iter().find_map(|asset| {
                let name = asset.get("name")?.as_str()?;
                if name.to_lowercase().ends_with(".dmg") {
                    asset
                        .get("browser_download_url")?
                        .as_str()
                        .map(|s| s.to_string())
                } else {
                    None
                }
            })
        });
    Ok((tag, dmg))
}

/// Loose version comparison. We don't need full semver ordering —
/// "is the latest tag different from what's installed" is enough to
/// surface an Update button, and treating any difference as
/// updatable avoids mis-parsing a non-semver tag into a false
/// "up to date". Leading `v` and surrounding whitespace are ignored.
fn norm(v: &str) -> String {
    v.trim().trim_start_matches(['v', 'V']).to_string()
}

fn one_status(app: &AppRef) -> AppStatus {
    let installed_version = app
        .bundle_name
        .as_deref()
        .and_then(installed_version);
    let installed = installed_version.is_some();

    let mut latest_version = None;
    let mut download_url = None;
    let mut error = None;

    match app.channel {
        Channel::Github => {
            if let Some(repo) = app.github_repo.as_deref() {
                match github_latest(repo) {
                    Ok((tag, dmg)) => {
                        if !tag.is_empty() {
                            latest_version = Some(tag);
                        }
                        download_url = dmg;
                    }
                    Err(e) => error = Some(e.to_string()),
                }
            }
        }
        Channel::Dmg => {
            download_url = app.url.clone();
        }
        Channel::Appstore | Channel::Library => {}
    }

    let updatable = match (&installed_version, &latest_version) {
        (Some(iv), Some(lv)) if !iv.is_empty() => norm(iv) != norm(lv),
        _ => false,
    };

    AppStatus {
        id: app.id.clone(),
        installed,
        installed_version,
        latest_version,
        download_url,
        updatable,
        error,
    }
}

/// Resolve status for the whole catalog. Runs on a blocking thread
/// (each entry may do a network round-trip to GitHub) so it doesn't
/// stall Tauri's async runtime.
#[tauri::command]
pub async fn app_statuses(apps: Vec<AppRef>) -> Result<Vec<AppStatus>, String> {
    tauri::async_runtime::spawn_blocking(move || {
        apps.iter().map(one_status).collect::<Vec<_>>()
    })
    .await
    .map_err(|e| format!("status probe join error: {e}"))
}
