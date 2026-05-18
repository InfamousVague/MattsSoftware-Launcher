/// Right-side slide-over with the full story for one app: large
/// icon, tagline, the "why it exists" pitch, description, tags,
/// version readout (installed vs latest), and the primary +
/// secondary actions. Closes on backdrop click / Escape / the X.

import { useEffect } from "react";
import { Button } from "@base/primitives/button";
import "@base/primitives/button/button.css";
import { Icon } from "@base/primitives/icon";
import "@base/primitives/icon/icon.css";
import { x as xIcon } from "@base/primitives/icon/icons/x";
import { folderOpen } from "@base/primitives/icon/icons/folder-open";
import { trash2 } from "@base/primitives/icon/icons/trash-2";
import { ActionButton } from "./ActionButton";
import type { CatalogApp } from "../data/catalog";
import type { AppStatus, InstallProgress } from "../lib/tauri";
import { revealApp } from "../lib/tauri";

interface Props {
  app: CatalogApp | null;
  status?: AppStatus;
  progress?: InstallProgress;
  onClose: () => void;
  onInstall: (app: CatalogApp) => void;
  onOpen: (app: CatalogApp) => void;
  onUninstall: (app: CatalogApp) => void;
}

function VersionRow({
  label,
  value,
}: {
  label: string;
  value: string;
}) {
  return (
    <div className="ms-detail__verrow">
      <span className="ms-detail__verlabel">{label}</span>
      <span className="ms-detail__verval">{value}</span>
    </div>
  );
}

export function AppDetail({
  app,
  status,
  progress,
  onClose,
  onInstall,
  onOpen,
  onUninstall,
}: Props) {
  // Escape closes; lock the listener to the panel's lifetime.
  useEffect(() => {
    if (!app) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [app, onClose]);

  if (!app) return null;

  return (
    <div
      className="ms-detail__scrim"
      onClick={onClose}
      role="presentation"
    >
      <aside
        className="ms-detail"
        role="dialog"
        aria-modal="true"
        aria-label={`${app.name} details`}
        onClick={(e) => e.stopPropagation()}
      >
        <button
          type="button"
          className="ms-detail__close"
          onClick={onClose}
          aria-label="Close"
        >
          <Icon icon={xIcon} size="sm" color="currentColor" />
        </button>

        <header className="ms-detail__head">
          <img
            className="ms-detail__icon"
            src={app.icon}
            alt=""
            draggable={false}
          />
          <div>
            <h2 className="ms-detail__name">{app.name}</h2>
            <p className="ms-detail__tagline">{app.tagline}</p>
            <span className="ms-detail__cat">{app.category}</span>
          </div>
        </header>

        <div className="ms-detail__actions">
          <ActionButton
            app={app}
            status={status}
            progress={progress}
            size="lg"
            onInstall={onInstall}
            onOpen={onOpen}
          />
          <ActionButton
            app={app}
            status={status}
            progress={progress}
            size="lg"
            secondary
            onInstall={onInstall}
            onOpen={onOpen}
          />
        </div>

        {app.pitch && <p className="ms-detail__pitch">{app.pitch}</p>}
        <p className="ms-detail__desc">{app.description}</p>

        <div className="ms-detail__tags">
          {app.tags.map((t) => (
            <span key={t} className="ms-tag">
              {t}
            </span>
          ))}
        </div>

        {(status?.installed || status?.latest_version) && (
          <div className="ms-detail__versions">
            {status?.installed && (
              <VersionRow
                label="Installed"
                value={
                  status.installed_version
                    ? status.installed_version
                    : "version unknown"
                }
              />
            )}
            {status?.latest_version && (
              <VersionRow
                label="Latest"
                value={status.latest_version}
              />
            )}
            {status?.error && (
              <VersionRow label="Note" value={status.error} />
            )}
          </div>
        )}

        {status?.installed && app.bundleName && (
          <div className="ms-detail__manage">
            <Button
              variant="ghost"
              size="sm"
              icon={folderOpen}
              onClick={() => void revealApp(app.bundleName as string)}
            >
              Reveal in Finder
            </Button>
            <Button
              variant="ghost"
              size="sm"
              intent="error"
              icon={trash2}
              onClick={() => onUninstall(app)}
            >
              Uninstall
            </Button>
          </div>
        )}
      </aside>
    </div>
  );
}
