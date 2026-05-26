import AppKit
import Combine
import Observation
import SuiteKit
import SwiftUI

/// Polls every merged pane's `paneLiveActivity()` plus the shared
/// on-disk payloads written by standalone agents (Worktree,
/// Seasick, …) into one ranked list. The `NotchHost` renders the
/// top-priority entry in the compact pill and stacks the rest in
/// the expanded state.
///
/// 1 Hz polling cadence: matches Espresso's countdown precision,
/// is imperceptible on the wattage budget, and avoids the
/// publisher gymnastics of subscribing to every pane's internal
/// state changes across an `@objc` dylib boundary.
@MainActor
@Observable
final class LiveActivityCoordinator {

    /// Normalised activity ready for the UI. Source-agnostic —
    /// pane payloads and file payloads both reduce to this shape
    /// so the renderer doesn't care where it came from.
    struct Resolved: Identifiable, Equatable {
        let id: String
        let compactLeadingImage: NSImage?
        let compactTrailingText: String?
        let compactTrailingImage: NSImage?
        let tint: Color
        let priority: Int
        /// Pane-supplied expanded panel (NSHostingView from a
        /// SwiftUI view inside the pane's dylib). nil ⇒ standalone
        /// or pane that opted out of expansion — tap-to-expand is
        /// a no-op for these.
        let expandedView: NSView?

        static func == (l: Resolved, r: Resolved) -> Bool {
            // Identity + the bits the UI renders. Equality is
            // used to suppress redundant SwiftUI invalidations.
            l.id == r.id &&
            l.compactTrailingText == r.compactTrailingText &&
            l.priority == r.priority &&
            l.tint == r.tint
        }
    }

    /// All currently-active payloads, sorted high → low priority.
    private(set) var activities: [Resolved] = []

    /// The winning payload — first non-nil entry of `activities`,
    /// rendered in the compact pill.
    var topActivity: Resolved? { activities.first }

    @ObservationIgnored private weak var suiteHost: SuiteHost?
    @ObservationIgnored private var pollTimer: Timer?
    /// Lifetime of activity payloads written to disk. Beyond this
    /// the file is treated as stale (writer crashed without
    /// clearing) and ignored.
    @ObservationIgnored private let payloadTTL: TimeInterval = 30

    init(suiteHost: SuiteHost) {
        self.suiteHost = suiteHost
    }

    func start() {
        pollOnce()
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.pollOnce() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Polling

    private func pollOnce() {
        var collected: [Resolved] = []
        // 1) In-process panes (merged into the launcher's process)
        if let suiteHost {
            for (id, pane) in suiteHost.loadedPanes {
                guard let payload = pane.paneLiveActivity?() else {
                    continue
                }
                collected.append(Self.resolve(payload, id: id))
            }
        }
        // 2) Out-of-process standalones via the shared JSON store
        collected.append(contentsOf: pollSharedStore())
        // Stable sort: priority desc, then id asc so ties don't
        // flicker between frames.
        collected.sort {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.id < $1.id
        }
        // Only republish when something actually changed — keeps
        // the SwiftUI invalidation graph quiet.
        if collected != activities {
            activities = collected
        }
    }

    private static func resolve(_ payload: SuiteLiveActivity,
                                id: String) -> Resolved {
        Resolved(
            id: id,
            compactLeadingImage: payload.compactLeadingImage,
            compactTrailingText: payload.compactTrailingText,
            compactTrailingImage: payload.compactTrailingImage,
            tint: Self.color(hex: payload.tintHex),
            priority: payload.priority,
            expandedView: payload.expandedView
        )
    }

    /// Read every `<id>.json` payload in the shared directory,
    /// drop stale ones, return resolved entries. Symbol names get
    /// mapped to template NSImages on this side so the renderer
    /// stays homogeneous.
    private func pollSharedStore() -> [Resolved] {
        let fm = FileManager.default
        let dir = SuiteLiveActivityStore.directory
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])
        else { return [] }
        let now = Date().timeIntervalSince1970
        var out: [Resolved] = []
        for url in entries where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let p = try? JSONDecoder().decode(
                    SuiteLiveActivityStore.Payload.self, from: data)
            else { continue }
            if now - p.updatedAt > payloadTTL { continue }
            let id = url.deletingPathExtension().lastPathComponent
            out.append(Resolved(
                id: id,
                compactLeadingImage: Self.symbolImage(p.compactLeadingSymbol),
                compactTrailingText: p.compactTrailingText,
                compactTrailingImage: Self.symbolImage(p.compactTrailingSymbol),
                tint: Self.color(hex: p.tintHex),
                priority: p.priority,
                expandedView: nil
            ))
        }
        return out
    }

    // MARK: - Helpers

    /// "#RRGGBB" → Color. Returns .white for anything we can't parse
    /// rather than throwing — bad hex shouldn't blank the pill.
    private static func color(hex: String) -> Color {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            return .white
        }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    /// Resolve a stored SF Symbol name to a template NSImage so
    /// the renderer can tint it the same way pane-supplied images
    /// are tinted.
    private static func symbolImage(_ name: String?) -> NSImage? {
        guard let name, !name.isEmpty,
              let img = NSImage(systemSymbolName: name,
                                accessibilityDescription: nil)
        else { return nil }
        img.isTemplate = true
        return img
    }
}
