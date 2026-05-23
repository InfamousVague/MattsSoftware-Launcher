import AppKit
import Foundation
import SwiftUI

/// Observable store the menu binds to: a status map, a per-app
/// "busy phase" map, a refresh, and install/open actions — with
/// installs serialised through a single chained Task so two
/// `hdiutil` mounts never race.
@MainActor
final class AppState: ObservableObject {
    @Published var statuses: [String: AppStatus] = [:]
    @Published var busy: [String: String] = [:]
    @Published var loading = false
    @Published var lastRefreshed: Date?

    /// Tail of the install chain. Each install awaits the prior one
    /// so they run strictly FIFO, one at a time.
    private var installTail: Task<Void, Never> = Task {}

    /// Set by `AppDelegate`: jump the launcher's switcher to a
    /// merged pane (selecting its tab + showing the popover) instead
    /// of bouncing through the standalone .app. Lets the catalog's
    /// "Open" action route a merged app directly to its tab — no
    /// brief standalone-launch flash.
    var openMergedPane: ((String) -> Void)?

    func refresh() async {
        loading = true
        // Publish each app's status as it lands instead of waiting
        // for the whole batch. The old batched-at-end publish made
        // every tile uninstallable until the slowest GitHub-API
        // resolver returned — and a click before that landed dead-
        // linked to the releases page through primaryAction's
        // `guard st?.downloadURL else { openExternal(releases) }`
        // fallback. With incremental publish, each tile becomes
        // clickable the moment its own `resolveStatus` resolves
        // (which is instant for any repo cached on disk). The
        // Launchpad-grid badges absorb the per-tile state changes
        // without the row-by-row visual jitter that the original
        // batched-publish was preventing.
        await withTaskGroup(
            of: (String, AppStatus).self
        ) { group in
            for app in CATALOG {
                group.addTask {
                    (app.id, await Services.resolveStatus(app))
                }
            }
            for await (id, st) in group { statuses[id] = st }
        }
        loading = false
        lastRefreshed = Date()
    }

    func primaryAction(_ app: CatalogApp) {
        switch app.channel {
        case .appstore, .library:
            if let u = app.url { Services.openExternal(u) }
            return
        case .github, .dmg:
            break
        }
        let st = statuses[app.id]
        // Installed + current → just open it (routed through
        // openInstalled so merged panes jump to their tab).
        if st?.installed == true, st?.updatable == false,
           app.bundleName != nil {
            openInstalled(app)
            return
        }
        guard let url = st?.downloadURL else {
            // No macOS .dmg on the latest release (or a transient
            // GitHub error). Don't dead-click: open the releases
            // page so the user can still get the build, and show a
            // brief, self-clearing reason instead of silently doing
            // nothing.
            if app.channel == .github, let repo = app.githubRepo {
                let full =
                    repo.contains("/")
                    ? repo : "\(GITHUB_OWNER)/\(repo)"
                Services.openExternal(
                    "https://github.com/\(full)/releases")
            }
            let why =
                st?.error
                ?? "No macOS build on the latest release — opened releases"
            busy[app.id] = why
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if busy[app.id] == why { busy[app.id] = nil }
            }
            return
        }
        enqueueInstall(app, url: url)
    }

    func openInstalled(_ app: CatalogApp) {
        // If this app is a SuiteKit pane AND set to Merged, jump
        // straight to its tab inside the launcher — no standalone
        // .app bounce. Standalone-pinned apps fall through to the
        // normal NSWorkspace open.
        if SuiteHost.registry.contains(where: { $0.id == app.id }),
           !SuiteSettings.isStandalone(app.id),
           let jump = openMergedPane {
            jump(app.id)
            return
        }
        if let bn = app.bundleName { Services.openApp(bn) }
    }

    /// Quit (if running) → move the bundle to the Trash → refresh.
    /// Caller (the row) has already confirmed with the user.
    func uninstall(_ app: CatalogApp) {
        guard let bn = app.bundleName else { return }
        busy[app.id] = "Uninstalling…"
        Task {
            let err: String? = await Task.detached {
                Services.forceQuit(bn)
                do {
                    try Services.trashApp(bn)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            if let err {
                busy[app.id] = "Failed: \(err)"
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if busy[app.id]?.hasPrefix("Failed") == true {
                    busy[app.id] = nil
                }
            } else {
                busy[app.id] = nil
                await refresh()
            }
        }
    }

    /// Updatable apps, in catalog order — what the header's
    /// "N updates" chip counts and "Update all" walks.
    var updatable: [CatalogApp] {
        CATALOG.filter { statuses[$0.id]?.updatable == true }
    }

    /// Queue every pending update at once (each still installs
    /// FIFO through the shared chain, so no two `hdiutil` mounts
    /// race). No-op for apps already busy.
    func updateAll() {
        for app in updatable where busy[app.id] == nil {
            if let url = statuses[app.id]?.downloadURL {
                enqueueInstall(app, url: url)
            }
        }
    }

    private func enqueueInstall(_ app: CatalogApp, url: String) {
        let waiting = !busy.isEmpty
        busy[app.id] = waiting ? "Queued…" : "Starting…"
        let prior = installTail
        installTail = Task { [weak self] in
            await prior.value
            guard let self else { return }
            await self.runInstall(app, url: url)
        }
    }

    private func runInstall(_ app: CatalogApp, url: String) async {
        let bn = app.bundleName
        let isSelf = app.id == "mattssoftware"
        let isUpdate = statuses[app.id]?.installed == true
        do {
            // The launcher can't ditto over its own running bundle:
            // selfUpdate hands the swap to a detached helper that
            // waits for us to exit, replaces the app, and relaunches
            // it — so we quit right after it returns.
            if isSelf {
                try await Services.selfUpdate(
                    downloadURL: url
                ) { msg in
                    Task { @MainActor in self.busy[app.id] = msg }
                }
                busy[app.id] = "Relaunching…"
                try? await Task.sleep(nanoseconds: 600_000_000)
                NSApplication.shared.terminate(nil)
                return
            }

            // Update/replace: forcefully close the running copy
            // first (as requested), install, then reopen it.
            var wasRunning = false
            if let bn {
                wasRunning = await Task.detached {
                    Services.isRunning(bn)
                }.value
                if isUpdate || wasRunning {
                    busy[app.id] = "Quitting \(app.name)…"
                    await Task.detached {
                        Services.forceQuit(bn)
                    }.value
                }
            }

            _ = try await Services.installApp(
                app, downloadURL: url
            ) { msg in
                Task { @MainActor in self.busy[app.id] = msg }
            }

            if let bn, isUpdate || wasRunning {
                busy[app.id] = "Reopening \(app.name)…"
                Services.openApp(bn)
            }
            busy[app.id] = nil
            await refresh()
        } catch {
            busy[app.id] = "Failed: \(error.localizedDescription)"
            // Leave the failure visible briefly, then clear so the
            // row returns to an actionable state.
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if busy[app.id]?.hasPrefix("Failed") == true {
                busy[app.id] = nil
            }
        }
    }
}
