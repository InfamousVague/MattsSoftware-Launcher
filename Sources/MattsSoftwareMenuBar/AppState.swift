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

    func refresh() async {
        loading = true
        // Resolve every app concurrently, then publish together so
        // the menu doesn't flicker row-by-row.
        let resolved = await withTaskGroup(
            of: (String, AppStatus).self
        ) { group -> [String: AppStatus] in
            for app in CATALOG {
                group.addTask {
                    (app.id, await Services.resolveStatus(app))
                }
            }
            var acc: [String: AppStatus] = [:]
            for await (id, st) in group { acc[id] = st }
            return acc
        }
        statuses = resolved
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
        // Installed + current → just open it.
        if st?.installed == true, st?.updatable == false,
           let bn = app.bundleName {
            Services.openApp(bn)
            return
        }
        guard let url = st?.downloadURL else {
            busy[app.id] =
                st?.error ?? "No download available yet"
            return
        }
        enqueueInstall(app, url: url)
    }

    func openInstalled(_ app: CatalogApp) {
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
