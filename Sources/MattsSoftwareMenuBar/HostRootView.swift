import SwiftUI
import AppKit

/// The popover's real root once the suite is unified: a thin segment
/// switcher on top, the selected pane below. "APPS" is the built-in
/// catalog (`MenuContentView`); every other segment is a feature
/// loaded at runtime from an installed app.
struct HostRootView: View {
    @EnvironmentObject private var state: AppState
    let host: SuiteHost

    var body: some View {
        VStack(spacing: 0) {
            switcher
            Divider()
            content
        }
        // Matches MenuContentView's 380 so the catalog grid fits
        // 4 columns. Merged panes (340pt internally) keep their
        // own width and centre inside the wider popover envelope.
        .frame(width: 380)
    }

    // MARK: Switcher

    private var switcher: some View {
        // ScrollViewReader so we can centre the active tab whenever
        // the selection changes — particularly important when opening
        // a fresh pane appends a new tab to the right edge that would
        // otherwise be offscreen.
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(host.entries) { e in
                        let on = host.selected == e.id
                        let isExternal = e.openURL != nil
                        Button {
                            if isExternal { host.openExternal(e.id) }
                            // openMerged lazily fires up the pane's
                            // runtime the first time it's opened — at
                            // launcher boot nothing was paneStart-ed.
                            else { host.openMerged(e.id) }
                        } label: {
                            // Browser-tab style: just the pane title.
                            // Active tab gets an accent-coloured pill
                            // so there's never any doubt which view
                            // you're looking at; needs-update keeps
                            // its small orange dot beside the label.
                            HStack(spacing: 4) {
                                Text(e.title)
                                    .font(.system(
                                        size: 11,
                                        weight: on ? .semibold : .medium))
                                    .foregroundStyle(on
                                        ? Color.white : Color.secondary)
                                    .lineLimit(1)
                                if e.needsUpdate {
                                    Circle().fill(.orange)
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 22)
                            .background(
                                on ? Color.accentColor : Color.clear,
                                in: Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        // Explicit id so ScrollViewReader.scrollTo
                        // can find the tab even with ForEach's own
                        // identity diffing (the two aren't the same).
                        .id(e.id)
                        .help(isExternal
                              ? "\(e.title) — open standalone"
                              : (e.needsUpdate
                                 ? "\(e.title) — update it to use it here"
                                 : e.title))
                    }

                    Divider().frame(height: 14).padding(.horizontal, 4)

                    let gearOn = host.selected == "settings"
                    Button { host.selected = "settings" } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .foregroundStyle(gearOn
                                ? Color.white : Color.secondary)
                            .background(
                                gearOn ? Color.accentColor : Color.clear,
                                in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .id("settings")
                    .help("Merge settings — choose which apps fold in here")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .onChange(of: host.selected) { _, newID in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
            // First-render selection (e.g. the launcher boots with a
            // pane already selected, or the popover reopens on a
            // previously-opened tab) lands centred too.
            .onAppear {
                proxy.scrollTo(host.selected, anchor: .center)
            }
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if host.selected == "settings" {
            SuiteSettingsView(host: host)
        } else if host.selected == "apps" {
            MenuContentView()
        } else if let e = host.entries.first(where: {
            $0.id == host.selected
        }) {
            if let v = e.view {
                PaneContainer(view: v)
                    .frame(maxWidth: .infinity)
            } else {
                needsUpdateNotice(e.title)
            }
        } else {
            MenuContentView()
        }
    }

    private func needsUpdateNotice(_ title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.up.circle")
                .font(.system(size: 26))
                .foregroundStyle(.orange)
            Text("\(title) is out of date")
                .font(.system(size: 13, weight: .semibold))
            Text("This MattsSoftware build expects a newer "
                + "\(title). Update it to use it here, or open "
                + "it standalone.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(width: 340, height: 540)
    }
}
