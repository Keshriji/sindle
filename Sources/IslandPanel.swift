import SwiftUI
import AppKit

/// Borderless, transparent window pinned to the top-centre of the screen.
final class IslandPanel: NSPanel {
    /// Width of the camera housing, read from the free space either side of it. Used so the island's
    /// left and right "wings" sit outside the notch instead of behind it.
    static var notchWidth: CGFloat {
        guard let s = NSScreen.main, let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea,
              s.frame.width > l.width + r.width else { return 190 }
        return s.frame.width - l.width - r.width
    }

    static let size = CGSize(width: 560, height: 250)

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
        contentView = NSHostingView(rootView: IslandView(player: player, weather: weather, lyrics: lyrics, status: status, tools: tools, audio: audio))
        reposition()
    }

    func reposition() {
        guard let screen = NSScreen.main else { return }
        let f = screen.frame
        setFrame(NSRect(x: f.midX - Self.size.width / 2,
                        y: f.maxY - Self.size.height,
                        width: Self.size.width, height: Self.size.height),
                 display: true)
    }
    override var canBecomeKey: Bool { true }   // lets text fields (notes, tasks) take typing
}
