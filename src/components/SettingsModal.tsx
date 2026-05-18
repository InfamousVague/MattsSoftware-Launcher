/// The launcher's single settings surface — a Base Dialog with the
/// handful of preferences a launcher needs. Theme + accent apply
/// live (they just flip the documentElement attributes the Base kit
/// reads); everything persists to the backend settings.json on
/// change so it survives relaunch.

import { Dialog } from "@base/primitives/dialog";
import "@base/primitives/dialog/dialog.css";
import { Toggle } from "@base/primitives/toggle";
import "@base/primitives/toggle/toggle.css";
import type { LauncherSettings } from "../lib/tauri";

interface Props {
  open: boolean;
  settings: LauncherSettings;
  onClose: () => void;
  onChange: (next: LauncherSettings) => void;
}

function Row({
  title,
  hint,
  children,
}: {
  title: string;
  hint: string;
  children: React.ReactNode;
}) {
  return (
    <div className="ms-setrow">
      <div className="ms-setrow__text">
        <div className="ms-setrow__title">{title}</div>
        <div className="ms-setrow__hint">{hint}</div>
      </div>
      <div className="ms-setrow__control">{children}</div>
    </div>
  );
}

export function SettingsModal({
  open,
  settings,
  onClose,
  onChange,
}: Props) {
  const patch = (p: Partial<LauncherSettings>) =>
    onChange({ ...settings, ...p });

  return (
    <Dialog
      open={open}
      onClose={onClose}
      title="Settings"
      description="Preferences for the MattsSoftware launcher."
      size="md"
    >
      <div className="ms-settings">
        <Row
          title="Dark mode"
          hint="The launcher's overall appearance."
        >
          <Toggle
            label="Dark mode"
            checked={settings.theme === "dark"}
            onChange={(e) =>
              patch({ theme: e.target.checked ? "dark" : "light" })
            }
          />
        </Row>

        <Row
          title="Coloured accent"
          hint="Use the chromatic accent instead of the default monochrome."
        >
          <Toggle
            label="Coloured accent"
            checked={settings.accent_color}
            onChange={(e) => patch({ accent_color: e.target.checked })}
          />
        </Row>

        <Row
          title="Check for updates on launch"
          hint="Re-probe every app for a newer release when the launcher opens."
        >
          <Toggle
            label="Check for updates on launch"
            checked={settings.auto_check_updates}
            onChange={(e) =>
              patch({ auto_check_updates: e.target.checked })
            }
          />
        </Row>

        <Row
          title="Launch after install"
          hint="Open an app automatically once it finishes installing."
        >
          <Toggle
            label="Launch after install"
            checked={settings.launch_after_install}
            onChange={(e) =>
              patch({ launch_after_install: e.target.checked })
            }
          />
        </Row>

        <p className="ms-settings__foot">
          MattsSoftware · built with the Base design system
        </p>
      </div>
    </Dialog>
  );
}
