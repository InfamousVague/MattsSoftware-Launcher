import SwiftUI

/// The dropdown panel. A compact mirror of the launcher window:
/// every catalogued app as a row with its live status + one smart
/// action (Install / Update / Open / App Store / Source), a
/// refresh, and quit.
struct MenuContentView: View {
    @EnvironmentObject private var state: AppState

    private var updatableCount: Int {
        CATALOG.filter { state.statuses[$0.id]?.updatable == true }
            .count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(CATALOG) { app in
                        AppRow(app: app)
                            .environmentObject(state)
                        if app.id != CATALOG.last?.id {
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
            .frame(maxHeight: 420)
            Divider()
            footer
        }
        .frame(width: 360)
        .task {
            if state.statuses.isEmpty { await state.refresh() }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("MattsSoftware").font(.headline)
                Text(
                    updatableCount > 0
                        ? "\(updatableCount) update\(updatableCount > 1 ? "s" : "") available"
                        : "Every app I've built, in one place"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await state.refresh() }
            } label: {
                if state.loading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("Re-check installed apps + updates")
        }
        .padding(12)
    }

    private var footer: some View {
        HStack {
            if let t = state.lastRefreshed {
                Text("Updated \(t.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct AppRow: View {
    let app: CatalogApp
    @EnvironmentObject private var state: AppState

    private var status: AppStatus? { state.statuses[app.id] }
    private var busyMsg: String? { state.busy[app.id] }

    /// Smart action label — the Swift mirror of the launcher's
    /// ActionButton state machine.
    private var actionLabel: String {
        if let b = busyMsg { return b }
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

    private var statusLine: String {
        switch app.channel {
        case .library: return "Design system"
        case .appstore: return "Mac App Store"
        case .github, .dmg: break
        }
        if let s = status {
            if s.installed, s.updatable {
                return
                    "v\(s.installedVersion ?? "?") → \(s.latestVersion ?? "new")"
            }
            if s.installed {
                let v = s.installedVersion ?? ""
                return v.isEmpty
                    ? "Installed" : "Installed · \(v)"
            }
            if s.error != nil { return "Couldn't check" }
        }
        return "Not installed"
    }

    private var isBusy: Bool {
        guard let b = busyMsg else { return false }
        return !b.hasPrefix("Failed")
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.system(size: 13, weight: .semibold))
                Text(statusLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(actionLabel) {
                state.primaryAction(app)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .disabled(isBusy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contextMenu {
            if status?.installed == true, app.bundleName != nil {
                Button("Open") { state.openInstalled(app) }
            }
        }
    }
}
