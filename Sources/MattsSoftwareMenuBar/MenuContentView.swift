import AppKit
import SwiftUI

/// The popover panel — Launchpad-style grid of every catalogued app.
/// Each cell is a squircle icon with the app name beneath; tapping
/// runs the smart action (Install / Update / Open / App Store /
/// Source) and a long-press / right-click surfaces the full menu
/// (Reinstall, View releases, Uninstall, …).
///
/// Two sections so the user can scan their installed apps at a
/// glance without scrolling past the unfamiliar ones:
///   • Installed — apps where `status.installed == true`
///   • Available — everything else (not yet installed, or status
///     not yet known on first popover open)
///
/// Update affordance: each tile carries a small "↓" badge in the
/// top-right corner when the catalog has flagged an update —
/// no extra text, just an iconographic hint matching macOS
/// Tahoe's App Store style.
struct MenuContentView: View {
    @EnvironmentObject private var state: AppState

    /// 4 columns × 42pt icons fits the 340-wide popover (which
    /// matches every merged pane's width, so the launcher stays a
    /// single consistent size as the user switches tabs). Math:
    /// 340 − 24 (horizontal padding) = 316 available; the macOS
    /// ScrollView eats ~16pt for its scrollbar when "Show scroll
    /// bars" is set to Always, leaving 300pt of true grid width.
    /// 4 cells at min 62 + 3 gaps at 12 = 284 — 16pt of safety
    /// margin even with the scrollbar showing, so the adaptive
    /// layout doesn't fall back to 3 cols when content overflows.
    private let columns = [
        GridItem(.adaptive(minimum: 62, maximum: 74),
                 spacing: 12, alignment: .top)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            grid
            Divider()
            footer
        }
        // 340 to match every merged pane's intrinsic width — keeps
        // the launcher one consistent size across tab switches so
        // the popover doesn't visibly resize between APPS and the
        // panes. Smaller cells (42pt icons, 62pt min cell) earn
        // back the 4-column grid that used to need 380, and they
        // survive the scrollbar showing up under "Always" mode.
        .frame(width: 340, height: 540)
        .task {
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
                        .font(.system(size: 9, weight: .bold,
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
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(state.loading
                                     ? Color.accentColor : .secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: Grid

    /// Split the catalog into installed vs. everything else. Inside
    /// each section, sort alphabetically by name so the layout
    /// doesn't shuffle when the status set comes back from the
    /// network refresh.
    private var sortedSections: (installed: [CatalogApp],
                                 available: [CatalogApp]) {
        let installed = CATALOG.filter {
            state.statuses[$0.id]?.installed == true
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name)
                    == .orderedAscending }
        let installedIDs = Set(installed.map(\.id))
        let available = CATALOG.filter {
            !installedIDs.contains($0.id)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name)
                    == .orderedAscending }
        return (installed, available)
    }

    private var grid: some View {
        let (installed, available) = sortedSections
        return ScrollView {
            LazyVStack(spacing: 0,
                       pinnedViews: [.sectionHeaders]) {
                if !installed.isEmpty {
                    Section {
                        gridSection(installed)
                    } header: {
                        sectionHeader("Installed",
                                      count: installed.count)
                    }
                }
                if !available.isEmpty {
                    Section {
                        gridSection(available)
                    } header: {
                        sectionHeader("Available",
                                      count: available.count)
                    }
                }
            }
            .glassScrollers()
        }
        .frame(maxHeight: .infinity)
    }

    private func gridSection(_ apps: [CatalogApp]) -> some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(apps) { app in
                AppTile(app: app)
                    .environmentObject(state)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func sectionHeader(_ title: String,
                               count: Int) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.secondary)
            Spacer()
            PaddedCount(count)
                .font(.system(size: 10, weight: .medium,
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
                .help("Update all (\(updatableCount))")
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

// MARK: - Tile

/// One app in the grid. Squircle icon, name underneath, badges on
/// the icon corners for state. Click = primary action (Install /
/// Open / Update / etc.); right-click / long-press = full menu.
private struct AppTile: View {
    let app: CatalogApp
    @EnvironmentObject private var state: AppState

    private var status: AppStatus? { state.statuses[app.id] }
    private var busyMsg: String? { state.busy[app.id] }
    private var isInstalled: Bool { status?.installed == true }
    private var isUpdatable: Bool { status?.updatable == true }
    private var isWorking: Bool {
        guard let b = busyMsg else { return false }
        return !b.hasPrefix("Failed") && !b.hasPrefix("No ")
    }
    private var hasError: Bool {
        guard let b = busyMsg else { return false }
        return b.hasPrefix("Failed") || b.hasPrefix("No ")
    }
    private var canUninstall: Bool {
        guard isInstalled, app.bundleName != nil,
              app.id != "mattssoftware"
        else { return false }
        return app.channel == .github || app.channel == .dmg
    }

    private func confirmUninstall() {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "Uninstall \(app.name)?"
        a.informativeText = "\(app.name) will be quit and moved to "
            + "the Trash. You can put it back from the Trash later."
        a.addButton(withTitle: "Uninstall")
        a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn {
            state.uninstall(app)
        }
    }

    private var releasesURL: String? {
        guard let repo = app.githubRepo else { return nil }
        let full = repo.contains("/")
            ? repo : "\(GITHUB_OWNER)/\(repo)"
        return "https://github.com/\(full)/releases"
    }

    @ViewBuilder private var icon: some View {
        if let img = Services.appIcon(app.iconAsset) {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(
                    cornerRadius: 10, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.18))
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: "app.dashed")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary))
        }
    }

    /// Tiny iconographic badge in the top-right corner of the icon.
    /// One of three states max so the tile never gets cluttered:
    /// working spinner → update arrow → error triangle.
    @ViewBuilder private var statusBadge: some View {
        if isWorking {
            Circle()
                .fill(.background)
                .frame(width: 18, height: 18)
                .overlay(
                    ProgressView()
                        .controlSize(.mini)
                )
                .overlay(Circle().stroke(
                    Color.primary.opacity(0.12), lineWidth: 0.5))
        } else if isUpdatable {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white, Color.accentColor)
                .background(
                    Circle()
                        .fill(.background)
                        .frame(width: 18, height: 18))
        } else if hasError {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white, .orange)
                .background(
                    Circle()
                        .fill(.background)
                        .frame(width: 18, height: 18))
        }
    }

    /// Tap action — matches the old row's primary button. Channels
    /// that don't install (App Store / library) just open the URL.
    private func primaryTap() {
        guard busyMsg == nil else { return }  // already working
        state.primaryAction(app)
    }

    @ViewBuilder private var menuItems: some View {
        if isInstalled, app.bundleName != nil {
            Button("Open") { state.openInstalled(app) }
        }
        if isUpdatable {
            Button("Update") { state.primaryAction(app) }
        } else if !isInstalled,
                  app.channel == .github || app.channel == .dmg {
            Button("Install") { state.primaryAction(app) }
        } else if app.channel == .github,
                  status?.downloadURL != nil, isInstalled {
            Button("Reinstall") { state.primaryAction(app) }
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
           let u = app.url {
            Button(app.channel == .appstore
                   ? "Open in App Store" : "Open source") {
                Services.openExternal(u)
            }
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                icon
                    .opacity(isInstalled || isWorking ? 1 : 0.92)
                statusBadge
                    .offset(x: 4, y: -4)
            }
            Text(app.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 62)
        }
        .contentShape(Rectangle())
        .onTapGesture { primaryTap() }
        .contextMenu { menuItems }
        .help(busyMsg ?? app.tagline)
    }
}
