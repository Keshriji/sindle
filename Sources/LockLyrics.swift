import SwiftUI
import AppKit

/// Puts a window into its own high-level "space" using private SkyLight calls so it can sit above the lock screen.
/// Loaded with dlopen so the app still builds and runs if Apple changes or removes these functions.
enum SkyLight {
    private typealias MainConn = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
    private static var space: Int32?

    @discardableResult
    static func moveToLockSpace(windowNumber: Int) -> Bool {
        guard let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let a = dlsym(h, "SLSMainConnectionID"), let b = dlsym(h, "SLSSpaceCreate"),
              let c = dlsym(h, "SLSSpaceSetAbsoluteLevel"), let d = dlsym(h, "SLSShowSpaces"),
              let e = dlsym(h, "SLSSpaceAddWindowsAndRemoveFromSpaces") else { return false }
        let cid = unsafeBitCast(a, to: MainConn.self)()
        if space == nil {
            let sp = unsafeBitCast(b, to: SpaceCreate.self)(cid, 1, 0)
            _ = unsafeBitCast(c, to: SetLevel.self)(cid, sp, 400)
            _ = unsafeBitCast(d, to: ShowSpaces.self)(cid, [NSNumber(value: sp)] as CFArray)
            space = sp
        }
        _ = unsafeBitCast(e, to: AddWindows.self)(cid, space!, [NSNumber(value: windowNumber)] as CFArray, 7)
        return true
    }
}

/// Full-screen lock art at layer 1000 — the same layer Needle uses. That is above the wallpaper
/// but below the lock screen's clock and password field, so the system clock stays visible and the
/// field keeps working. The panel is click-through; clicks are hit-tested by LockLyrics.
final class LockLyricsPanel: NSPanel {
    init(player: NowPlaying, lyrics: LyricsStore) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        alphaValue = 0
        contentView = NSHostingView(rootView:
            LockScreenView(player: player, lyrics: lyrics)
                .environment(\.colorScheme, .dark))
    }

    func present() {
        guard let screen = NSScreen.main else { return }
        setFrame(screen.frame, display: true)
        alphaValue = 1
        orderFrontRegardless()
        SkyLight.moveToLockSpace(windowNumber: windowNumber)
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            animator().alphaValue = 0
        }
    }
}

/// Lyrics on the desktop, in the same style you picked for the lock screen. Drag it anywhere.
final class DesktopLyricsPanel: NSPanel {
    init(player: NowPlaying, lyrics: LyricsStore) {
        super.init(contentRect: NSRect(x: 120, y: 380, width: 560, height: 210),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isMovableByWindowBackground = true
        contentView = NSHostingView(rootView: DesktopLyricsView(player: player, lyrics: lyrics))
    }
}

struct DesktopLyricsView: View {
    @ObservedObject var player: NowPlaying
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var s = SettingsStore.shared
    @State private var tint = Color.white

    var body: some View {
        LockScreenLyrics(lyrics: lyrics, track: player.track, size: CGSize(width: 520, height: 170), u: 8,
                         style: s.lyricStyle, tint: tint, colorMode: s.lyricColorMode,
                         custom: Color(red: s.lyricR, green: s.lyricG, blue: s.lyricB),
                         nextOn: s.lockNextLineOn, scatter: s.lyricScatter, burst: 0)
            .padding(20)
            .frame(width: 560, height: 210)
            .background(RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.35)))
            .environment(\.colorScheme, .dark)
            .task(id: player.track?.artworkURL) { if let c = await AlbumColor.from(player.track?.artworkURL) { tint = c } }
    }
}

/// Shows the full-screen lock art when the Mac locks and hides it on unlock. The art window is
/// click-through so it can sit below the clock and password field; clicks are hit-tested with the
/// same layout the view uses. In the 10-second preview the panel is interactive instead, so the
/// record, cover and controls can be tried directly.
final class LockLyrics {
    private let player: NowPlaying, lyrics: LyricsStore
    private var panel: LockLyricsPanel?
    private var clickMonitor: Any?
    private var previewWork: DispatchWorkItem?
    private var previewing = false
    init(player: NowPlaying, lyrics: LyricsStore) { self.player = player; self.lyrics = lyrics }

    func start() {
        let c = DistributedNotificationCenter.default()
        c.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.show(preview: false) }
        c.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.hide() }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.panel?.present()
        }
    }

    func show(preview: Bool) {
        guard SettingsStore.shared.lockLyricsOn || preview else { return }
        if panel == nil { panel = LockLyricsPanel(player: player, lyrics: lyrics) }
        guard let panel else { return }
        previewing = preview
        if !preview { click("Tink") }        // a click as your Mac locks, like a phone
        panel.ignoresMouseEvents = !preview
        panel.present()
        installMonitor(active: !preview)
        if preview {
            previewWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            previewWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
        }
    }

    func hide() {
        previewWork?.cancel(); previewWork = nil
        installMonitor(active: false)
        if !previewing { click("Pop") }       // and a lighter click as it unlocks
        previewing = false
        panel?.dismiss()
    }

    private func click(_ name: String) {
        guard SettingsStore.shared.lockSoundsOn else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    private func installMonitor(active: Bool) {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor); self.clickMonitor = nil }
        guard active else { return }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            self?.handleClick()
        }
    }

    private func handleClick() {
        guard let panel, panel.alphaValue > 0 else { return }
        let mouse = NSEvent.mouseLocation
        guard panel.frame.contains(mouse) else { return }
        let local = CGPoint(x: mouse.x - panel.frame.minX, y: panel.frame.maxY - mouse.y)
        let m = LockMetrics(size: panel.frame.size)
        let mode = LockMode(rawValue: SettingsStore.shared.lockStage) ?? .lyrics
        switch lockHit(local, m, mode, controls: SettingsStore.shared.lockControlsOn) {
        case .advance: advance(mode)
        case .previous: player.send("previous track")
        case .playpause: player.send("playpause")
        case .next: player.send("next track")
        case .none: break
        }
    }

    private func advance(_ mode: LockMode) {
        let next = LockMode(rawValue: (mode.rawValue + 1) % 3) ?? .record
        withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.8)) {
            SettingsStore.shared.lockStage = next.rawValue
        }
    }
}

// MARK: view
struct Star { let x: CGFloat, y: CGFloat, size: CGFloat, phase: Double }

struct StarField: View {
    private let stars: [Star] = (0..<80).map { _ in
        Star(x: .random(in: 0...1), y: .random(in: 0...1), size: .random(in: 1...3.2), phase: .random(in: 0...6.28))
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                for s in stars {
                    ctx.opacity = 0.2 + 0.8 * (0.5 + 0.5 * sin(t * 1.6 + s.phase))      // twinkle
                    ctx.fill(Path(ellipseIn: CGRect(x: s.x * size.width, y: s.y * size.height, width: s.size, height: s.size)),
                             with: .color(.white))
                }
            }
        }
    }
}

/// Average colour of an album cover, brightened so it stays readable.
enum AlbumColor {
    static func from(_ url: URL?) async -> Color? {
        guard let url, let (d, _) = try? await URLSession.shared.data(from: url),
              let img = NSImage(data: d), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        px.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.interpolationQuality = .medium
            ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let r = Double(px[0]) / 255, g = Double(px[1]) / 255, b = Double(px[2]) / 255
        let m = max(r, g, b, 1.0 / 255)
        return Color(red: r / m, green: g / m, blue: b / m)
    }
}
