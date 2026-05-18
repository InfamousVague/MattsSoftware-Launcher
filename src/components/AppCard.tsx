/// One app tile in the grid: big icon, name, tagline, a status
/// chip, and the smart action button. The whole card is clickable
/// (opens the detail panel); the action button stops propagation so
/// "Install" doesn't also open the panel.
///
/// Note: the status chip + tags are plain token-styled spans rather
/// than Base's Badge/Tag primitives. Those two specific Base files
/// carry an unused-React import that trips this project's
/// `noUnusedLocals` (same strict tsconfig Libre uses); rather than
/// weaken the lint or patch the shared library, we render the chip
/// ourselves using the exact same Base design tokens — visually
/// identical, no dependency on the buggy files. Everything else
/// (Card, Button, Dialog, Input, Toggle, Spinner, Icon) is Base.

import { Card } from "@base/primitives/card";
import "@base/primitives/card/card.css";
import { ActionButton } from "./ActionButton";
import type { CatalogApp } from "../data/catalog";
import type { AppStatus, InstallProgress } from "../lib/tauri";

interface Props {
  app: CatalogApp;
  status?: AppStatus;
  progress?: InstallProgress;
  onSelect: (app: CatalogApp) => void;
  onInstall: (app: CatalogApp) => void;
  onOpen: (app: CatalogApp) => void;
}

type ChipTone = "neutral" | "success" | "warning" | "info";

function Chip({
  tone,
  children,
}: {
  tone: ChipTone;
  children: React.ReactNode;
}) {
  return (
    <span className={`ms-chip ms-chip--${tone}`}>{children}</span>
  );
}

function StatusChip({
  app,
  status,
}: {
  app: CatalogApp;
  status?: AppStatus;
}) {
  if (app.channel === "library")
    return <Chip tone="neutral">Library</Chip>;
  if (app.channel === "appstore")
    return <Chip tone="info">App Store</Chip>;
  if (status?.installed && status.updatable)
    return <Chip tone="warning">Update available</Chip>;
  if (status?.installed)
    return (
      <Chip tone="success">
        Installed
        {status.installed_version ? ` · ${status.installed_version}` : ""}
      </Chip>
    );
  if (status?.error) return <Chip tone="neutral">Not checked</Chip>;
  return <Chip tone="neutral">Not installed</Chip>;
}

export function AppCard({
  app,
  status,
  progress,
  onSelect,
  onInstall,
  onOpen,
}: Props) {
  return (
    <div
      className="ms-card-wrap"
      role="button"
      tabIndex={0}
      onClick={() => onSelect(app)}
      onKeyDown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onSelect(app);
        }
      }}
    >
      <Card variant="outlined" padding="none" interactive>
        <div className="ms-card">
          <img
            className="ms-card__icon"
            src={app.icon}
            alt=""
            draggable={false}
          />
          <div className="ms-card__body">
            <div className="ms-card__head">
              <h3 className="ms-card__name">{app.name}</h3>
              <StatusChip app={app} status={status} />
            </div>
            <p className="ms-card__tagline">{app.tagline}</p>
            <div className="ms-card__foot">
              <span className="ms-card__cat">{app.category}</span>
              <span
                className="ms-card__action"
                onClick={(e) => e.stopPropagation()}
              >
                <ActionButton
                  app={app}
                  status={status}
                  progress={progress}
                  size="sm"
                  onInstall={onInstall}
                  onOpen={onOpen}
                />
              </span>
            </div>
          </div>
        </div>
      </Card>
    </div>
  );
}
