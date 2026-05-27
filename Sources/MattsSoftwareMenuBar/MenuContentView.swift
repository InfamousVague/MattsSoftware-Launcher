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

    /// 4 columns × 54pt icons in the 340-wide popover. Math:
    /// 340 − 16 (section padding) − 16 (scrollbar under
    /// "Always" mode) = 308 of true grid width. 4 cells at
    /// min 72 + 3 gaps at 6 = 306 — 2pt of safety margin with
    /// the scrollbar showing. Without the scrollbar, the cells
    /// expand to fill (308 + 16 = 324 ÷ 4 ≈ 76pt each), well
    /// inside the [72, 82] band the adaptive layout picks
    /// through. Less padding + bigger icons = more room for
    /// the hover-video preview.
    private let columns = [
        GridItem(.adaptive(minimum: 72, maximum: 82),
                 spacing: 6, alignment: .top)
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
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(apps) { app in
                AppTile(app: app)
                    .environmentObject(state)
            }
        }
        .padding(.horizontal, 8)
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
    /// True while the cursor is over this tile's icon. Flips the
    /// hover-video on; the player rewinds + plays from frame
    /// zero each time this transitions true.
    @State private var isHovering = false
    /// Latches true when the video reaches its last frame so the
    /// crossfade-out plays even though the cursor is still hovering.
    /// Reset whenever a new hover begins.
    @State private var videoFinished = false

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

    /// Icon edge size. Bumped from 42pt to 54pt — the grid now
    /// gives each cell 72-82pt of horizontal room, so the icon
    /// can grow without crowding the per-app label below.
    private static let iconSize: CGFloat = 54
    /// Squircle corner radius for both the static icon and the
    /// video crop. ~22% of the icon edge so it matches macOS app
    /// icon styling at this size.
    private static let iconRadius: CGFloat = 12

    @ViewBuilder private var icon: some View {
        if let img = Services.appIcon(app.iconAsset) {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: Self.iconSize, height: Self.iconSize)
                .clipShape(RoundedRectangle(
                    cornerRadius: Self.iconRadius,
                    style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: Self.iconRadius,
                             style: .continuous)
                .fill(Color.secondary.opacity(0.18))
                .frame(width: Self.iconSize, height: Self.iconSize)
                .overlay(
                    Image(systemName: "app.dashed")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary))
        }
    }

    /// Video URL for this app's hover preview, or nil if no
    /// `anim-<iconAsset>.mp4` is bundled.
    private var hoverVideoURL: URL? {
        HoverVideoCatalog.url(forIcon: app.iconAsset)
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

    /// Crossfade rule: the static icon sits underneath at full
    /// opacity always. The video overlay is on top and fades in
    /// only while the cursor is over the tile AND the clip hasn't
    /// played through yet. When the AVPlayer fires its end
    /// notification, `videoFinished` flips true → overlay opacity
    /// animates back to 0 → static icon appears underneath. Same
    /// behaviour on early hover-out.
    private var videoOverlayActive: Bool {
        isHovering && !videoFinished && hoverVideoURL != nil
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                // Static icon — always present underneath so the
                // crossfade from video → icon is just the video's
                // opacity dropping.
                icon
                    .opacity(isInstalled || isWorking ? 1 : 0.92)

                // Hover-video overlay. Built only when a bundled
                // `anim-<id>.mp4` exists; otherwise the tile
                // renders as it always did. AVPlayer instance is
                // retained inside the NSViewRepresentable so its
                // first hover doesn't pay decoding setup latency.
                if let url = hoverVideoURL {
                    HoverVideoPlayer(
                        url: url,
                        isPlaying: videoOverlayActive,
                        onEnd: {
                            // Player paused on the last frame
                            // (actionAtItemEnd = .pause); the
                            // crossfade out happens here.
                            videoFinished = true
                        })
                        .frame(width: Self.iconSize,
                               height: Self.iconSize)
                        .clipShape(RoundedRectangle(
                            cornerRadius: Self.iconRadius,
                            style: .continuous))
                        .opacity(videoOverlayActive ? 1 : 0)
                        .animation(
                            .easeInOut(duration: 0.35),
                            value: videoOverlayActive)
                        .allowsHitTesting(false)
                }

                statusBadge
                    .offset(x: 4, y: -4)
            }
            Text(app.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 72)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                // Fresh hover → reset the played-through latch
                // BEFORE the player starts so the overlay's
                // opacity binding evaluates as active on the
                // same frame the AVPlayer rewinds + plays.
                videoFinished = false
            }
            isHovering = hovering
        }
        .onTapGesture { primaryTap() }
        .contextMenu { menuItems }
        .help(busyMsg ?? app.tagline)
    }
}
