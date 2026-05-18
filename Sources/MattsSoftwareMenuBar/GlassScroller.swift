import AppKit
import SwiftUI

/// Forces a SwiftUI `ScrollView`'s underlying `NSScrollView` to the
/// translucent **overlay** scroller with no drawn background.
///
/// Why: with the system "Show scroll bars" set to *Always* (or in a
/// material/glass popover) AppKit renders the *legacy* scroller —
/// an opaque black track that looks terrible against the glass.
/// There's no SwiftUI API to force the overlay style, so we reach
/// the enclosing scroll view via a zero-size companion NSView and
/// flip it. If the scroll view can't be found we simply no-op (the
/// scrollbar just stays as-is — never a crash).
///
/// Usage: attach to the *content inside* the ScrollView so the
/// companion view lives in the document view hierarchy:
///
///     ScrollView { LazyVStack { … }.glassScrollers() }
private struct ScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        v.setFrameSize(.zero)
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            var scroll = nsView.enclosingScrollView
            if scroll == nil {
                var s: NSView? = nsView.superview
                while let cur = s {
                    if let found = cur as? NSScrollView {
                        scroll = found
                        break
                    }
                    s = cur.superview
                }
            }
            guard let sv = scroll else { return }
            sv.scrollerStyle = .overlay
            sv.drawsBackground = false
            sv.backgroundColor = .clear
            sv.contentView.drawsBackground = false
            sv.verticalScroller?.scrollerStyle = .overlay
            sv.horizontalScroller?.scrollerStyle = .overlay
        }
    }
}

extension View {
    /// Glass-ify the enclosing ScrollView's scrollers (translucent
    /// overlay, no opaque track). Attach to the scroll *content*.
    func glassScrollers() -> some View {
        background(ScrollViewConfigurator())
    }
}
