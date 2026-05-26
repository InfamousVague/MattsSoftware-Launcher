import AppKit
import SwiftUI

/// Owns the borderless NSPanel that lives at the top of the
/// screen and renders the launcher's Dynamic-Island-style pill.
/// Coordinates with `LiveActivityCoordinator` (which decides
/// *what* to show) by hosting a SwiftUI `NotchView` that reads
/// the coordinator's `@Observable` state.
///
/// Positioning:
/// - Notched MacBook (14"/16" Pro, MBA M2/M3 13"/15"): uses
///   `NSScreen.auxiliaryTopLeftArea`/`.auxiliaryTopRightArea` to
///   know the notch's exact bounds and anchors the pill to its
///   trailing edge.
/// - Non-notched displays (Mac mini, external monitors, older
///   laptops): renders the pill centred at the top of the screen
///   instead — a software approximation rather than a hardware
///   blend, but visually present so the feature works
///   everywhere.
@MainActor
final class NotchHost: NSObject {

    let coordinator: LiveActivityCoordinator
    private weak var suiteHost: SuiteHost?

    private var panel: NSPanel?
    private var hostingController: NSHostingController<NotchHostRoot>?
    private var screenObserver: NSObjectProtocol?

    /// Master toggle. When false, the panel is torn down entirely
    /// — no offscreen window, no polling timer hits, zero CPU.
    private(set) var isEnabled: Bool = false

    init(suiteHost: SuiteHost) {
        self.suiteHost = suiteHost
        self.coordinator = LiveActivityCoordinator(suiteHost: suiteHost)
        super.init()
    }

    /// Enables the feature: builds the panel + starts the
    /// coordinator. Idempotent.
    func enable() {
        NSLog("[island] enable() called, isEnabled=\(isEnabled)")
        guard !isEnabled else { return }
        isEnabled = true
        rebuildPanel()
        coordinator.start()
        // Rebuild the panel whenever the screen layout changes —
        // user docks/undocks an external display, the notch
        // becomes (un)available, etc.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rebuildPanel() }
        }
    }

    func disable() {
        guard isEnabled else { return }
        isEnabled = false
        if let o = screenObserver {
            NotificationCenter.default.removeObserver(o)
            screenObserver = nil
        }
        coordinator.stop()
        panel?.orderOut(nil)
        panel = nil
        hostingController = nil
    }

    // MARK: - Window

    private func rebuildPanel() {
        // Re-resolving the host screen each rebuild so an unplug
        // event doesn't leave us pinned to a screen that's gone.
        guard let screen = NSScreen.main else {
            NSLog("[island] rebuildPanel: no main screen, bailing")
            return
        }
        let layout = NotchLayout.resolve(for: screen)
        NSLog("[island] layout: hasNotch=\(layout.hasNotch) notchTrailingX=\(layout.notchTrailingX) screenWidth=\(layout.screenWidth)")

        // Panel covers the full notch band horizontally but is
        // only ~160pt tall — enough room for the expanded pill to
        // grow down into without ever colliding with app content.
        // The visible black pill draws inside this transparent
        // window; clicks fall through outside the pill thanks to
        // `ignoresMouseEvents` on the empty parts and the pill's
        // explicit contentShape.
        let panelRect = NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - layout.panelHeight,
            width: screen.frame.width,
            height: layout.panelHeight
        )

        if panel == nil {
            // .nonactivatingPanel only — drop the .borderless because
            // SwiftUI inside a borderless NSPanel can fail to draw if
            // the contentView's initial layer isn't materialised (a
            // long-standing macOS quirk). Without title styling but
            // with nonactivating, the panel still has no chrome and
            // doesn't steal focus.
            let p = NSPanel(
                contentRect: panelRect,
                styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.isMovable = false
            p.isFloatingPanel = true
            // `.popUpMenu` sits above status-bar items (which also
            // float at `.statusBar`/`.mainMenu` z) so a packed
            // menu bar can't render *over* the pill. Still below
            // `.modalPanel` so it never breaks modal stacking.
            p.level = .popUpMenu
            p.collectionBehavior = [
                .canJoinAllSpaces,
                .stationary,
                .fullScreenAuxiliary,
                .ignoresCycle,
            ]
            // Let clicks pass through to apps below for the empty
            // regions of the panel; the pill itself re-asserts a
            // contentShape so taps still register on it.
            p.ignoresMouseEvents = false  // pill needs taps
            p.hidesOnDeactivate = false
            panel = p
        } else {
            panel?.setFrame(panelRect, display: false, animate: false)
        }

        let root = NotchHostRoot(
            coordinator: coordinator,
            layout: layout
        )

        if let hc = hostingController {
            hc.rootView = root
        } else {
            let hc = NSHostingController(rootView: root)
            hc.view.wantsLayer = true
            hc.view.layer?.backgroundColor = NSColor.clear.cgColor
            // Pin the host view's autoresizing so it matches the
            // panel's content rect even when SwiftUI's intrinsic
            // size collapses to zero (which it will, given the
            // .frame(maxWidth: .infinity) we use to let the pill
            // float-position inside a screen-wide canvas).
            hc.view.autoresizingMask = [.width, .height]
            hostingController = hc
            panel?.contentViewController = hc
        }

        // contentViewController sizing can shrink the window to
        // the controller's intrinsic content size — which is zero
        // for our infinity-framed SwiftUI root. Re-assert the
        // panel frame AFTER the controller's been attached so it
        // doesn't collapse. Also size the host view explicitly so
        // SwiftUI has a real bounds to render against.
        panel?.setFrame(panelRect, display: true, animate: false)
        hostingController?.view.frame = NSRect(
            origin: .zero, size: panelRect.size)

        panel?.orderFrontRegardless()
        NSLog("[island] panel after orderFront: visible=\(panel?.isVisible ?? false) frame=\(panel?.frame ?? .zero) level=\(panel?.level.rawValue ?? 0) contentView=\(panel?.contentView?.frame ?? .zero)")
    }
}

/// SwiftUI root the `NotchHost` mounts inside its `NSHostingController`.
/// Subscribes to `LiveActivityCoordinator` (Observable) so the
/// pill re-renders when payloads change, without the host having
/// to wire any KVO bridges itself.
struct NotchHostRoot: View {
    @Bindable var coordinator: LiveActivityCoordinator
    let layout: NotchLayout

    var body: some View {
        NotchView(
            activities: coordinator.activities,
            notchTrailingX: layout.notchTrailingX,
            hasNotch: layout.hasNotch,
            screenWidth: layout.screenWidth
        )
    }
}

/// One spot for "where does the pill go on THIS screen" math.
/// Resolves notch presence + bounds + the safe horizontal anchor
/// the pill snaps to.
struct NotchLayout: Equatable {
    let hasNotch: Bool
    /// X coordinate (in the panel's local space, origin at left
    /// of screen) where the notch's trailing edge sits. The pill
    /// anchors just to the right of this. On non-notched
    /// displays, equals screenWidth/2 so the pill renders centred.
    let notchTrailingX: CGFloat
    let screenWidth: CGFloat
    /// Height of the host panel — big enough to contain the
    /// expanded pill drop without ever growing the window
    /// dynamically (which would jitter z-order).
    let panelHeight: CGFloat

    static func resolve(for screen: NSScreen) -> NotchLayout {
        let screenWidth = screen.frame.width
        // `auxiliaryTopLeftArea` / `.auxiliaryTopRightArea` return
        // non-nil rects only on notched displays. Their `maxX` /
        // `minX` flank the notch cutout exactly.
        if let leftAux = screen.auxiliaryTopLeftArea,
           let rightAux = screen.auxiliaryTopRightArea {
            // Both rects use screen coords (origin bottom-left).
            // Convert leftAux.maxX → panel-local x (origin at
            // screen.frame.minX, same axis).
            let notchLeading = leftAux.maxX - screen.frame.minX
            let notchTrailing = rightAux.minX - screen.frame.minX
            _ = notchLeading  // surfaced if a future left-pill needs it
            return NotchLayout(
                hasNotch: true,
                notchTrailingX: notchTrailing,
                screenWidth: screenWidth,
                panelHeight: 160
            )
        }
        return NotchLayout(
            hasNotch: false,
            notchTrailingX: screenWidth / 2,
            screenWidth: screenWidth,
            panelHeight: 160
        )
    }
}
