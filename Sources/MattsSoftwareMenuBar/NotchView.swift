import SwiftUI

/// Notch-band UI rendered inside the `NotchHostWindow`. The view
/// stretches to the screen-top band the host sized the window to,
/// then internally positions:
///
/// - **Compact**: a single small black pill sitting **just below**
///   the menu bar, offset to one side of the camera notch so it
///   visually pairs with the physical cutout (left or right
///   depending on which side has the space — on non-notched
///   displays it just sits centred).
/// - **Expanded**: the same pill grows downward and outward into a
///   rounded rectangle large enough for the active pane's
///   expanded view (~320×120pt).
///
/// Solid `#000` background, no shadow, no border: the goal is to
/// read as a hardware extension of the notch, not as another
/// floating widget.
struct NotchView: View {
    var activities: [LiveActivityCoordinator.Resolved]
    var notchTrailingX: CGFloat   // where the notch ends; pill anchors here
    var hasNotch: Bool             // false ⇒ centre the pill instead
    var screenWidth: CGFloat

    @State private var expanded: Bool = false
    /// Suppress the open-on-launch flash: the window appears with
    /// `activities` empty, slides in once a real one shows up.
    @State private var hasContent: Bool = false

    private let pillHeight: CGFloat = 28
    private let pillTopInset: CGFloat = 30  // sit just under menu bar
    private let expandedHeight: CGFloat = 132
    private let expandedWidth: CGFloat = 360

    var body: some View {
        ZStack(alignment: .top) {
            // Transparent backdrop — clicks land on the pill only.
            Color.clear

            if let top = activities.first {
                pill(for: top)
                    .position(
                        x: pillCenterX(width: expanded
                                       ? expandedWidth
                                       : compactWidth(for: top)),
                        y: pillTopInset + (expanded
                                           ? expandedHeight / 2
                                           : pillHeight / 2)
                    )
                    .animation(.spring(response: 0.32,
                                        dampingFraction: 0.78),
                               value: expanded)
                    .animation(.spring(response: 0.32,
                                        dampingFraction: 0.78),
                               value: top)
                    .onAppear { hasContent = true }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(hasContent ? 1 : 0)
    }

    // MARK: Pill content

    @ViewBuilder
    private func pill(for a: LiveActivityCoordinator.Resolved) -> some View {
        if expanded {
            expandedPill(for: a)
        } else {
            compactPill(for: a)
        }
    }

    private func compactPill(
        for a: LiveActivityCoordinator.Resolved
    ) -> some View {
        HStack(spacing: 6) {
            if let img = a.compactLeadingImage {
                Image(nsImage: tintImage(img, color: a.tint))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
            }
            if let text = a.compactTrailingText {
                Text(text)
                    .font(.system(size: 11, weight: .semibold,
                                  design: .rounded))
                    .foregroundStyle(a.tint)
                    .lineLimit(1)
            } else if let img = a.compactTrailingImage {
                Image(nsImage: tintImage(img, color: a.tint))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: pillHeight)
        .background(Color.black, in: Capsule())
        .contentShape(Capsule())
        .onTapGesture {
            // Only expand when the pane actually gave us
            // expanded content — otherwise the tap is a no-op.
            if a.expandedView != nil { expanded.toggle() }
        }
        // Subsequent activities (runners-up) get tiny tint dots
        // tucked at the right edge so the user can tell there's
        // more behind the compact pill.
        .overlay(alignment: .topTrailing) {
            if activities.count > 1 {
                HStack(spacing: 2) {
                    ForEach(activities.dropFirst().prefix(3)) { other in
                        Circle()
                            .fill(other.tint)
                            .frame(width: 4, height: 4)
                    }
                }
                .padding(.trailing, 6)
                .offset(y: 4)
            }
        }
    }

    private func expandedPill(
        for a: LiveActivityCoordinator.Resolved
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header mirrors the compact pill so the user
            // recognises the same activity expanded.
            HStack(spacing: 8) {
                if let img = a.compactLeadingImage {
                    Image(nsImage: tintImage(img, color: a.tint))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                }
                if let text = a.compactTrailingText {
                    Text(text)
                        .font(.system(size: 14, weight: .semibold,
                                      design: .rounded))
                        .foregroundStyle(a.tint)
                }
                Spacer()
                Button {
                    expanded = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            // Pane-supplied expanded content. We host the NSView
            // SwiftUI returned from the pane and let it own its
            // layout inside the remaining space.
            if let v = a.expandedView {
                NSViewWrapper(view: v)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14)
        .frame(width: expandedWidth, height: expandedHeight)
        .background(
            Color.black,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
    }

    // MARK: Layout

    private func compactWidth(
        for a: LiveActivityCoordinator.Resolved
    ) -> CGFloat {
        // Estimate: 24pt for the leading image slot + ~7pt per
        // trailing-text char + 24pt of padding. Capped so a
        // verbose payload doesn't blow out the pill.
        let textWidth: CGFloat = {
            guard let s = a.compactTrailingText else { return 0 }
            return min(CGFloat(s.count) * 7.5, 60)
        }()
        let leading: CGFloat = a.compactLeadingImage == nil ? 0 : 18
        let base: CGFloat = 24    // padding
        return max(64, leading + textWidth + base)
    }

    private func pillCenterX(width: CGFloat) -> CGFloat {
        if hasNotch {
            // Tuck the pill just to the right of the notch
            // trailing edge. When the pill grows wider than that
            // space allows, drift back toward centre so it never
            // disappears off-screen.
            let preferred = notchTrailingX + 10 + width / 2
            let maxCentre = screenWidth - width / 2 - 8
            return min(preferred, maxCentre)
        }
        return screenWidth / 2
    }

    /// Apply the activity's tint to a template image by re-fill.
    /// SF Symbols and template NSImages get their alpha mask
    /// painted with the tint colour so the brand colour reads.
    private func tintImage(_ img: NSImage, color: Color) -> NSImage {
        let nsColor = NSColor(color)
        let tinted = img.copy() as! NSImage
        tinted.isTemplate = false
        tinted.lockFocus()
        nsColor.set()
        let rect = NSRect(origin: .zero, size: tinted.size)
        rect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        return tinted
    }
}

/// Hosts a raw `NSView` (typically an `NSHostingView` produced
/// inside a pane's dylib) inside SwiftUI without copying its tree.
private struct NSViewWrapper: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
