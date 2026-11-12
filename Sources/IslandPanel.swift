import SwiftUI
import AppKit

/// Borderless, transparent window pinned to the top-centre of the screen.
final class IslandPanel: NSPanel {
    static let size = CGSize(width: 420, height: 190)

    init(player: NowPlaying, weather: WeatherStore, lyrics: LyricsStore, status: StatusStore, tools: Tools) {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovable = false
        contentView = NSHostingView(rootView: IslandView(player: player, weather: weather, lyrics: lyrics, status: status, tools: tools))
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
