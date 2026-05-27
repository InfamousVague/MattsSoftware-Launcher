import AppKit
import AVFoundation
import AVKit
import SwiftUI

/// Hover-driven video playback for an app tile. Sits on top of
/// the static icon; when `isPlaying` flips true the AVPlayer
/// rewinds + plays; when it flips false the player pauses. The
/// crossfade between the video and the icon underneath is owned
/// by the caller — this view just animates its own `opacity`
/// through SwiftUI binding state on the parent side.
///
/// Audio is intentionally never enabled; the source files have
/// no audio track but `.isMuted = true` belt-and-suspenders.
struct HoverVideoPlayer: NSViewRepresentable {
    let url: URL
    /// True while the parent wants playback. We start from t=0
    /// each time this flips true so every hover gets a fresh
    /// play-through.
    var isPlaying: Bool
    /// Fires when the AVPlayer reaches the end. The caller uses
    /// this to flip its own state and let the video fade out.
    var onEnd: () -> Void

    func makeNSView(context: Context) -> ContainerView {
        let view = ContainerView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        let player = AVPlayer(url: url)
        player.isMuted = true
        // Hold on the last frame instead of resetting to t=0 so
        // the crossfade-out doesn't briefly snap back to the
        // opening frame before the icon takes over.
        player.actionAtItemEnd = .pause

        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer?.addSublayer(layer)

        context.coordinator.player = player
        context.coordinator.layer = layer
        context.coordinator.onEnd = onEnd
        context.coordinator.observe(player: player)
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ContainerView, context: Context) {
        guard let player = context.coordinator.player else { return }
        context.coordinator.onEnd = onEnd
        // Resize the AVPlayerLayer to track frame changes.
        context.coordinator.layer?.frame = nsView.bounds
        if isPlaying {
            // Always rewind so a quick re-hover plays from the
            // start rather than wherever the previous run paused.
            player.seek(to: .zero,
                        toleranceBefore: .zero,
                        toleranceAfter: .zero)
            player.play()
        } else {
            player.pause()
        }
    }

    static func dismantleNSView(_ nsView: ContainerView,
                                coordinator: Coordinator) {
        coordinator.invalidate()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Custom NSView so we can drive layer-frame updates from
    /// `layout()` (SwiftUI changes the bounds on hover-state
    /// resizes and we'd otherwise see the video frozen at the
    /// makeNSView-time size).
    final class ContainerView: NSView {
        weak var coordinator: Coordinator?
        override func layout() {
            super.layout()
            coordinator?.layer?.frame = bounds
        }
    }

    @MainActor
    final class Coordinator {
        var player: AVPlayer?
        var layer: AVPlayerLayer?
        var onEnd: (() -> Void)?
        private var endObserver: NSObjectProtocol?

        func observe(player: AVPlayer) {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { [weak self] _ in
                self?.onEnd?()
            }
        }

        func invalidate() {
            if let o = endObserver {
                NotificationCenter.default.removeObserver(o)
                endObserver = nil
            }
            player?.pause()
            player = nil
        }
    }
}

/// Returns the URL of the bundled `anim-<id>.mp4` for an icon
/// asset id, or nil if no video ships for this app. Used by the
/// AppTile to decide whether to bother wiring the hover overlay
/// at all.
@MainActor
enum HoverVideoCatalog {
    static func url(forIcon iconAsset: String) -> URL? {
        Bundle.main.url(
            forResource: "anim-\(iconAsset)",
            withExtension: "mp4")
    }
}
