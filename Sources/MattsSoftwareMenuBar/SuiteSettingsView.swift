import SwiftUI

/// The "gear" pane: one row per app the launcher can absorb, with a
/// Merged⇄Standalone control. Merge-by-default, so this is where you
/// opt an app back out to its own menu-bar icon. Changing a row
/// takes effect immediately (quits/relaunches the standalone agent
/// and adds/removes the pane).
struct SuiteSettingsView: View {
    let host: SuiteHost
    /// Lazily read on first render so the toggle reflects whatever
    /// the user previously chose; updates synchronously when they
    /// flip it and propagates to `MattsSoftwareMenuBarApp.notchHost`
    /// via the binding.
    @State private var dynamicIslandOn: Bool
        = SuiteSettings.dynamicIslandEnabled()

    init(host: SuiteHost) {
        self.host = host
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    dynamicIslandRow
                    Divider().opacity(0.4)
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

    /// Top row in the settings list — toggles the notch-pinned
    /// pill on/off. Lives above the per-app merge rows because
    /// it's a launcher-wide preference, not per-app.
    private var dynamicIslandRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dynamic Island")
                    .font(.system(size: 12, weight: .semibold))
                Text("Pill near the notch for live activities")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { dynamicIslandOn },
                set: { on in
                    dynamicIslandOn = on
                    SuiteSettings.setDynamicIslandEnabled(on)
                    // Reach into the app delegate to flip the
                    // host live without a relaunch. The delegate
                    // owns the lazy `notchHost`; toggling here
                    // enables or tears it down immediately.
                    if let d = NSApp.delegate as? AppDelegate {
                        if on { d.notchHost.enable() }
                        else { d.notchHost.disable() }
                    }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
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
