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
        .frame(width: 340)
    }

    // MARK: Switcher

    private var switcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
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
                        // Just the app's full-colour squircle PNG,
                        // no chrome / cell padding. Unselected items
                        // dim slightly so the active tab stands out
                        // without a separate background ring.
                        Image(nsImage: e.image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(
                                cornerRadius: 14, style: .continuous))
                            .opacity(on ? 1 : 0.78)
                            .overlay(alignment: .topTrailing) {
                                if e.needsUpdate {
                                    Circle().fill(.orange)
                                        .frame(width: 6, height: 6)
                                        .offset(x: -1, y: 1)
                                }
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isExternal
                          ? "\(e.title) — open standalone"
                          : (e.needsUpdate
                             ? "\(e.title) — update it to use it here"
                             : e.title))
                }

                Divider().frame(height: 22).padding(.horizontal, 2)

                let gearOn = host.selected == "settings"
                Button { host.selected = "settings" } label: {
                    Image(systemName: "slider.horizontal.3")
                        .resizable().scaledToFit()
                        .frame(width: 22, height: 22)
                        .frame(width: 40, height: 40)
                        .foregroundStyle(gearOn
                                         ? Color.accentColor : .secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Merge settings — choose which apps fold in here")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
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
