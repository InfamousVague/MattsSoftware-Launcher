import AppKit
import SwiftUI

/// The popover panel — the whole app's UI. Every catalogued app as
/// a row with its live status, the real squircle icon, and one
/// smart action (Install / Update / Open / App Store / Source).
/// Visual language is shared 1:1 with the other MattsSoftware
/// menu-bar apps (Sentry, Port, Peephole, …): fixed-width panel,
/// uppercase tracked header, pinned category section headers on
/// `.ultraThinMaterial`, monospaced metadata, understated plain
/// footer controls.
struct MenuContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 380, height: 560)
        .task {
            // The delegate warms this on launch; the guard just
            // covers the (unlikely) case the popover opens first.
            if state.statuses.isEmpty { await state.refresh() }
        }
    }

    // MARK: Header

    private var updatableCount: Int { state.updatable.count }

    private var statusText: String {
        if state.loading { return "checking…" }
        guard let t = state.lastRefreshed else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return "updated \(f.string(from: t))"
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(alignment: .center, spacing: 6) {
                if let icon = Services.brandIcon {
                    // The `>|M` brandmark is a wide transparent glyph,
                    // not a square app squircle — keep its aspect and
                    // don't clip it into a rounded rect.
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(height: 14)
                } else {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 13))
                        .foregroundStyle(.tint)
                }
                Text("MATTSSOFTWARE")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(2)
                if updatableCount > 0 {
                    PaddedCount(updatableCount)
                        .font(
                            .system(
                                size: 9, weight: .bold,
                                design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.22))
                        .foregroundStyle(Color.accentColor)
                        .clipShape(Capsule())
                        .help(
                            "\(updatableCount) update\(updatableCount > 1 ? "s" : "") available"
                        )
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(CATALOG.count) apps")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(statusText)
                    .font(
                        .system(size: 10, design: .monospaced))
                    .foregroundStyle(
                        state.loading
                            ? Color.accentColor : .secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            LazyVStack(
                spacing: 0, pinnedViews: [.sectionHeaders]
            ) {
                ForEach(CATALOG_SECTIONS) { section in
                    Section {
                        ForEach(section.apps) { app in
                            AppRow(app: app)
                                .environmentObject(state)
                            Divider().opacity(0.4)
                        }
                    } header: {
                        sectionHeader(
                            section.category.rawValue,
                            count: section.apps.count)
                    }
                }
            }
            .glassScrollers()
        }
        .frame(maxHeight: .infinity)
    }

    private func sectionHeader(
        _ title: String, count: Int
    ) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.secondary)
            Spacer()
            PaddedCount(count)
                .font(
                    .system(
                        size: 10, weight: .medium,
                        design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                Task { await state.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .controlSize(.small)
            .help("Refresh")
            .disabled(state.loading)

            Spacer()

            if updatableCount > 0 {
                Button {
                    state.updateAll()
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .controlSize(.small)
                .help(
                    "Update all (\(updatableCount))")
            }

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .controlSize(.small)
            .help("Quit MattsSoftware")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - Row

private struct AppRow: View {
    let app: CatalogApp
    @EnvironmentObject private var state: AppState

    private var status: AppStatus? { state.statuses[app.id] }
    private var busyMsg: String? { state.busy[app.id] }

    /// A message is showing at all (working OR a terminal
    /// Failed/no-build notice). Either way the row shows the
    /// message, never the button — so a click is never swallowed.
    private var hasMessage: Bool { busyMsg != nil }

    /// Actively working → show a spinner. Failed/“No macOS build”
    /// are terminal notices (no spinner, tinted, self-clearing).
    private var isWorking: Bool {
        guard let b = busyMsg else { return false }
        return !b.hasPrefix("Failed") && !b.hasPrefix("No ")
    }

    private var isBusy: Bool { isWorking }

    /// An installed app we own the bundle for can be removed —
    /// except the launcher itself (you don't trash MattsSoftware
    /// from inside MattsSoftware) and non-installable channels.
    private var canUninstall: Bool {
        guard status?.installed == true, app.bundleName != nil,
              app.id != "mattssoftware"
        else { return false }
        return app.channel == .github || app.channel == .dmg
    }

    /// Confirm, then quit + Trash. NSAlert is modal on the main
    /// thread, which is where SwiftUI button actions already run.
    private func confirmUninstall() {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "Uninstall \(app.name)?"
        a.informativeText =
            "\(app.name) will be quit and moved to the Trash. "
            + "You can put it back from the Trash later."
        a.addButton(withTitle: "Uninstall")
        a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn {
            state.uninstall(app)
        }
    }

    /// Smart action label — the per-app action state machine.
    private var actionLabel: String {
        switch app.channel {
        case .appstore: return "App Store"
        case .library: return "Source"
        case .github, .dmg: break
        }
        if status?.installed == true, status?.updatable == true {
            return "Update"
        }
        if status?.installed == true { return "Open" }
        if let s = status, s.error != nil, s.downloadURL == nil {
            return "Retry"
        }
        return "Install"
    }

    /// Install / Update are the loud, get-the-app actions; the
    /// rest (Open / Source / App Store) stay quiet bordered.
    private var actionIsProminent: Bool {
        actionLabel == "Install" || actionLabel == "Update"
            || actionLabel == "Retry"
    }

    private var statusLine: String {
        switch app.channel {
        case .library: return "Design system · open source"
        case .appstore: return "Apple Watch · Mac App Store"
        case .github, .dmg: break
        }
        if let s = status {
            if s.installed, s.updatable {
                return
                    "v\(s.installedVersion ?? "?")  →  \(s.latestVersion ?? "new")"
            }
            if s.installed {
                let v = s.installedVersion ?? ""
                return v.isEmpty
                    ? "Installed · up to date"
                    : "Installed · v\(v)"
            }
            if s.error != nil { return "Couldn't check GitHub" }
            if let lv = s.latestVersion {
                return "Not installed · latest \(lv)"
            }
        }
        return "Not installed"
    }

    private var releasesURL: String? {
        guard let repo = app.githubRepo else { return nil }
        let full =
            repo.contains("/") ? repo : "\(GITHUB_OWNER)/\(repo)"
        return "https://github.com/\(full)/releases"
    }

    @ViewBuilder private var iconView: some View {
        if let img = Services.appIcon(app.iconAsset) {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(
                            Color.primary.opacity(0.10),
                            lineWidth: 0.5))
        } else {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "app.dashed")
                        .foregroundStyle(.secondary))
        }
    }

    @ViewBuilder private var actionControl: some View {
        if hasMessage {
            // Always render the message — working (spinner) OR a
            // terminal Failed / "No macOS build" notice. Never fall
            // back to the button here, so a click is never silently
            // swallowed (the bug behind "Update does nothing").
            HStack(spacing: 5) {
                if isWorking {
                    ProgressView().controlSize(.small)
                }
                Text(busyMsg ?? "Working…")
                    .font(.system(size: 10))
                    .foregroundStyle(
                        isWorking ? Color.secondary : Color.orange)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
            .frame(minWidth: 76, maxWidth: 150, alignment: .trailing)
        } else {
            Button(actionLabel) {
                state.primaryAction(app)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .tint(
                actionIsProminent
                    ? Color.accentColor : Color.secondary
            )
            .fixedSize()
        }
    }

    @ViewBuilder private var menuItems: some View {
        if status?.installed == true, app.bundleName != nil {
            Button("Open") { state.openInstalled(app) }
        }
        if app.channel == .github, status?.downloadURL != nil {
            Button(
                status?.installed == true ? "Reinstall" : "Install"
            ) { state.primaryAction(app) }
        }
        if let r = releasesURL {
            Button("View releases on GitHub") {
                Services.openExternal(r)
            }
        }
        if canUninstall {
            Divider()
            Button("Uninstall \(app.name)…", role: .destructive) {
                confirmUninstall()
            }
        }
        if app.channel == .appstore || app.channel == .library,
            let u = app.url
        {
            Button(
                app.channel == .appstore
                    ? "Open in App Store" : "Open source"
            ) { Services.openExternal(u) }
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            iconView
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(
                            .system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if status?.updatable == true {
                        Text("UPDATE")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Color.accentColor.opacity(0.20))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                Text(statusLine)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(
                        (status?.error != nil
                            && status?.downloadURL == nil)
                            ? Color.orange : .secondary
                    )
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if canUninstall && !isBusy {
                Button(action: confirmUninstall) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Uninstall \(app.name)")
            }
            actionControl
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu { menuItems }
        .help(app.tagline)
    }
}
