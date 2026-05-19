import SwiftUI

/// The "gear" pane: one row per app the launcher can absorb, with a
/// Merged⇄Standalone control. Merge-by-default, so this is where you
/// opt an app back out to its own menu-bar icon. Changing a row
/// takes effect immediately (quits/relaunches the standalone agent
/// and adds/removes the pane).
struct SuiteSettingsView: View {
    let host: SuiteHost

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(SuiteHost.registry) { app in
                        row(app)
                        Divider().opacity(0.4)
                    }
                }
            }
            .glassScrollers()
            Divider()
            footer
        }
        .frame(width: 340, height: 540)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12))
                .foregroundStyle(.tint)
            Text("MERGE SETTINGS")
                .font(.system(size: 13, weight: .semibold))
                .tracking(2)
            Spacer()
            Text("\(SuiteHost.registry.count) apps")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder private func row(_ app: SuiteHost.SuiteApp) -> some View {
        let available = host.appAvailable(app)
        let merged = !SuiteSettings.isStandalone(app.id)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.system(size: 12, weight: .semibold))
                Text(available
                     ? (merged ? "Shown here as a pane"
                               : "Runs as its own menu-bar app")
                     : "Not installed")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Picker("", selection: Binding(
                get: { merged },
                set: { host.setMerged(app, $0) }
            )) {
                Text("Merged").tag(true)
                Text("Standalone").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(!available)
            .opacity(available ? 1 : 0.4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var footer: some View {
        HStack {
            Text("Merge-by-default · installing an app adds it here")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
