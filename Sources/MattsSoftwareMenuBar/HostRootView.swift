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
        .frame(width: 380)
    }

    // MARK: Switcher

    private var switcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(host.entries) { e in
                    let on = host.selected == e.id
                    Button {
                        host.selected = e.id
                    } label: {
                        Image(nsImage: e.image)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 15, height: 15)
                            .frame(width: 34, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(on ? e.tint.opacity(0.22)
                                             : Color.clear))
                            .foregroundStyle(on ? e.tint : .secondary)
                            .overlay(alignment: .topTrailing) {
                                if e.needsUpdate {
                                    Circle().fill(.orange)
                                        .frame(width: 5, height: 5)
                                        .offset(x: -3, y: 3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .help(e.needsUpdate
                          ? "\(e.title) — update it to use it here"
                          : e.title)
                }

                Divider().frame(height: 16).padding(.horizontal, 2)

                let gearOn = host.selected == "settings"
                Button { host.selected = "settings" } label: {
                    Image(systemName: "slider.horizontal.3")
                        .resizable().scaledToFit()
                        .frame(width: 14, height: 14)
                        .frame(width: 34, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(gearOn
                                      ? Color.accentColor.opacity(0.22)
                                      : Color.clear))
                        .foregroundStyle(gearOn
                                         ? Color.accentColor : .secondary)
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
        .frame(width: 380, height: 320)
    }
}
