import SwiftUI
import AppKit

/// Borderless, transparent window pinned to the top-centre of the screen.
///
/// Two bugs came from this window being a fixed 560 x 250 box:
///  - the wide dashboard is 660 wide, so it overflowed; and SwiftUI then quietly stretched the window to fit it,
///    which left the next, smaller card 50 points off-centre;
///  - a big transparent box over the menu bar caught the pointer when you only passed near the notch.
/// Now the window is sized from the island itself (`fit`), kept centred, and SwiftUI is told not to resize it.
final class IslandPanel: NSPanel {
    static weak var current: IslandPanel?

    /// Width of the camera housing, read from the free space either side of it. Used so the island's
    /// left and right "wings" sit outside the notch instead of behind it.
    static var notchWidth: CGFloat {
        guard let s = NSScreen.main, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea,
              s.frame.width > l.width + r.width else { return 190 }
        return s.frame.width - l.width - r.width
    }

    private var target = CGSize(width: IslandPanel.notchWidth + 160, height: 70)
    private var shrinkWork: DispatchWorkItem?

    init(player: NowPlaying, weather: WeatherStore, lyrics: LyricsStore, status: StatusStore, tools: Tools, audio: AudioLevel) {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovable = false
        let host = NSHostingView(rootView: IslandView(player: player, weather: weather, lyrics: lyrics, status: status, tools: tools, audio: audio))
        host.sizingOptions = []                 // the content must never resize this window
        contentView = host
        Self.current = self
        reposition()
    }

    /// Resizes the window to hug the island plus room for its shadow, centred on the top edge. It grows at once
    /// (so the opening animation is never clipped) and shrinks only after the closing animation has finished.
    func fit(width: CGFloat, height: CGFloat) {
        let new = CGSize(width: ceil(width + 48), height: ceil(height + 28))
        guard new != target else { return }
        shrinkWork?.cancel()
        if new.width >= target.width && new.height >= target.height {
            target = new
            reposition()
        } else {
            let work = DispatchWorkItem { [weak self] in
                self?.target = new
                self?.reposition()
            }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: work)
        }
    }

    func reposition() {
        guard let screen = NSScreen.main else { return }
        let f = screen.frame
        setFrame(NSRect(x: f.midX - target.width / 2, y: f.maxY - target.height, width: target.width, height: target.height),
                 display: true)
    }

    override var canBecomeKey: Bool { true }   // lets text fields (notes, tasks) take typing
}
