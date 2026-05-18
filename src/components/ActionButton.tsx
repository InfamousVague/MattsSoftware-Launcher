/// The one button whose label/behaviour encodes the entire per-app
/// state machine: probing → install → update → open, plus the
/// non-installable channels (App Store / library) and error/retry.
/// Centralised so the card and the detail panel render identical
/// affordances from the same inputs.

import { Button } from "@base/primitives/button";
import "@base/primitives/button/button.css";
import { download } from "@base/primitives/icon/icons/download";
import { refreshCw } from "@base/primitives/icon/icons/refresh-cw";
import { arrowUpCircle } from "@base/primitives/icon/icons/arrow-up-circle";
import { play } from "@base/primitives/icon/icons/play";
import { externalLink } from "@base/primitives/icon/icons/external-link";
import { triangleAlert } from "@base/primitives/icon/icons/triangle-alert";
import type { CatalogApp } from "../data/catalog";
import type { AppStatus, InstallProgress } from "../lib/tauri";

interface Props {
  app: CatalogApp;
  status?: AppStatus;
  progress?: InstallProgress;
  size?: "sm" | "md" | "lg";
  /// Render the secondary (Open / source) affordance instead of the
  /// primary install/update one. Used on the detail panel where both
  /// can appear side by side.
  secondary?: boolean;
  onInstall: (app: CatalogApp) => void;
  onOpen: (app: CatalogApp) => void;
}

export function ActionButton({
  app,
  status,
  progress,
  size = "md",
  secondary = false,
  onInstall,
  onOpen,
}: Props) {
  const installing =
    progress &&
    progress.phase !== "done" &&
    progress.phase !== "error";
  const failed = progress?.phase === "error";

  // ── Secondary slot: Open (installed) / source (library/store) ──
  if (secondary) {
    if (status?.installed && app.bundleName) {
      return (
        <Button
          variant="secondary"
          size={size}
          icon={play}
          onClick={() => onOpen(app)}
        >
          Open
        </Button>
      );
    }
    return null;
  }

  // ── Mid-install: live phase, button locked ──
  if (installing) {
    return (
      <Button variant="primary" size={size} loading disabled>
        {progress?.message ?? "Working…"}
      </Button>
    );
  }

  // ── Install failed: retry, surface the reason via title ──
  if (failed) {
    return (
      <Button
        variant="primary"
        size={size}
        intent="error"
        appearance="outline"
        icon={triangleAlert}
        title={progress?.message}
        onClick={() => onInstall(app)}
      >
        Retry
      </Button>
    );
  }

  // ── Non-installable channels ──
  if (app.channel === "appstore") {
    return (
      <Button
        variant="primary"
        size={size}
        icon={externalLink}
        onClick={() => onInstall(app)}
      >
        App Store
      </Button>
    );
  }
  if (app.channel === "library") {
    return (
      <Button
        variant="secondary"
        size={size}
        icon={externalLink}
        onClick={() => onInstall(app)}
      >
        View source
      </Button>
    );
  }

  // ── Installed + newer available ──
  if (status?.installed && status.updatable) {
    return (
      <Button
        variant="primary"
        size={size}
        icon={arrowUpCircle}
        onClick={() => onInstall(app)}
        title={
          status.latest_version
            ? `Update to ${status.latest_version}`
            : "Update available"
        }
      >
        Update
      </Button>
    );
  }

  // ── Installed + current → Open ──
  if (status?.installed) {
    return (
      <Button
        variant="secondary"
        size={size}
        icon={play}
        onClick={() => onOpen(app)}
      >
        Open
      </Button>
    );
  }

  // ── Not installed: probe error vs ready-to-install ──
  if (status?.error && !status.download_url) {
    return (
      <Button
        variant="secondary"
        size={size}
        icon={refreshCw}
        title={`Couldn't check for a release: ${status.error}`}
        onClick={() => onInstall(app)}
      >
        Retry
      </Button>
    );
  }

  return (
    <Button
      variant="primary"
      size={size}
      icon={download}
      onClick={() => onInstall(app)}
    >
      Install
    </Button>
  );
}
