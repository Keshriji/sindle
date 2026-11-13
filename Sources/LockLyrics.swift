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

final class LockLyricsPanel: NSPanel {
    init(player: NowPlaying, lyrics: LyricsStore) {
        super.init(contentRect: NSScreen.main?.frame ?? .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false; ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = NSHostingView(rootView: LockLyricsView(player: player, lyrics: lyrics))
    }
    func present() {
        setFrame(NSScreen.main?.frame ?? .zero, display: true)
        orderFrontRegardless()
        SkyLight.moveToLockSpace(windowNumber: windowNumber)
    }
}

/// Small panel with play, pause and skip that also sits on the lock screen (it is tiny, so it never blocks the password field).
final class LockControlsPanel: NSPanel {
    init(player: NowPlaying) {
        let f = NSScreen.main?.frame ?? .zero
        super.init(contentRect: NSRect(x: f.midX - 135, y: f.minY + 28, width: 270, height: 52),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = NSHostingView(rootView: LockControls(player: player))
    }
    func present() {
        let f = NSScreen.main?.frame ?? .zero
        setFrame(NSRect(x: f.midX - 135, y: f.minY + 28, width: 270, height: 52), display: true)
        orderFrontRegardless()
        SkyLight.moveToLockSpace(windowNumber: windowNumber)
    }
}

struct LockControls: View {
    @ObservedObject var player: NowPlaying
    var body: some View {
        HStack(spacing: 30) {
            btn("backward.fill", "previous track"); btn("playpause.fill", "playpause"); btn("forward.fill", "next track")
            Button { SettingsStore.shared.lockStage = (SettingsStore.shared.lockStage + 1) % 3 } label: {
                Image(systemName: "square.stack").font(.system(size: 18)).foregroundStyle(.white.opacity(0.8))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 24).padding(.vertical, 12).background(Capsule().fill(.black.opacity(0.45)))
    }
    private func btn(_ icon: String, _ cmd: String) -> some View {
        Button { player.send(cmd) } label: { Image(systemName: icon).font(.system(size: 20)).foregroundStyle(.white) }
            .buttonStyle(.plain)
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
        contentView = NSHostingView(rootView:
            LockLyricsView(player: player, lyrics: lyrics, compact: true)
                .frame(width: 1400, height: 525).scaleEffect(0.4).frame(width: 560, height: 210)
                .background(RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.35))))
    }
}

/// Shows the panels when the Mac locks, hides them on unlock.
final class LockLyrics {
    private let player: NowPlaying, lyrics: LyricsStore
    private var panel: LockLyricsPanel?
    private var controls: LockControlsPanel?
    init(player: NowPlaying, lyrics: LyricsStore) { self.player = player; self.lyrics = lyrics }

    func start() {
        let c = DistributedNotificationCenter.default()
        c.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in self?.show(preview: false) }
        c.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in self?.hide() }
    }

    func show(preview: Bool) {
        guard SettingsStore.shared.lockLyricsOn || preview else { return }
        if panel == nil { panel = LockLyricsPanel(player: player, lyrics: lyrics) }
        if controls == nil { controls = LockControlsPanel(player: player) }
        panel?.present()
        if SettingsStore.shared.lockControlsOn || preview { controls?.present() }
        if preview { DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.hide() } }
    }
    func hide() { panel?.orderOut(nil); controls?.orderOut(nil) }
}

// MARK: view
struct Star { let x: CGFloat, y: CGFloat, size: CGFloat, phase: Double }

struct StarField: View {
    private let stars: [Star] = (0..<80).map { _ in
        Star(x: .random(in: 0...1), y: .random(in: 0...1), size: .random(in: 1...3.2), phase: .random(in: 0...6.28))
    }
    var body: some View {
        TimelineView(.animation) { tl in
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

/// A small burst of sparkles that flies out when a new line appears.
struct StarBurst: View {
    @State private var go = false
    var body: some View {
        ZStack {
            ForEach(0..<14, id: \.self) { i in
                let a = Double(i) / 14 * 2 * Double.pi
                Image(systemName: "sparkle")
                    .font(.system(size: 14 + CGFloat(i % 3) * 6))
                    .foregroundStyle(i % 2 == 0 ? Color.yellow : Color.white)
                    .offset(x: go ? CGFloat(cos(a)) * 210 : 0, y: go ? CGFloat(sin(a)) * 90 : 0)
                    .scaleEffect(go ? 0.3 : 1).opacity(go ? 0 : 1)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 1.1)) { go = true } }
    }
}

/// A vinyl record that turns under the lyrics, with the album cover as its label.
struct LockRecord: View {
    let url: URL?
    var size: CGFloat = 160
    var body: some View {
        TimelineView(.animation) { tl in
            let angle = (tl.date.timeIntervalSinceReferenceDate * 60).truncatingRemainder(dividingBy: 360)
            ZStack {
                Circle().fill(.black)
                ForEach([50, 62, 74], id: \.self) { r in
                    Circle().stroke(.white.opacity(0.08), lineWidth: 1).frame(width: CGFloat(r) * 2)
                }
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.4) }
                    .frame(width: 70, height: 70).clipShape(Circle())
                Circle().fill(.black).frame(width: 7)
            }
            .frame(width: 160, height: 160).scaleEffect(size / 160).frame(width: size, height: size)
            .rotationEffect(.degrees(angle))
            .shadow(color: .black.opacity(0.5), radius: 16)
        }
    }
}

struct LockLyricsView: View {
    @ObservedObject var player: NowPlaying
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var s = SettingsStore.shared
    var compact = false
    @State private var burst = 0
    @State private var albumTint = Color.white

    private var lyricColour: Color {
        switch s.lyricColorMode {
        case 1:  return albumTint
        case 2:  return Color(red: s.lyricR, green: s.lyricG, blue: s.lyricB)
        default: return .white
        }
    }

    private func text(_ k: Int) -> String { (k >= 0 && k < lyrics.lines.count) ? lyrics.lines[k].s : "" }

    /// 0...1 progress through the current line
    private func progress(_ t: Track?, _ i: Int?) -> Double {
        guard let t, let i, i < lyrics.lines.count else { return 0 }
        let start = lyrics.lines[i].t
        let end = i + 1 < lyrics.lines.count ? lyrics.lines[i + 1].t : start + 4
        return max(0, min(0.999, (t.position - start) / max(end - start, 0.5)))
    }

    var body: some View {
        let t = player.track
        let i = t.flatMap { lyrics.index(at: $0.position) }
        let cur = text(i ?? -1).isEmpty ? "♪" : text(i ?? -1)
        ZStack {
            if !compact { LinearGradient(colors: [.clear, .black.opacity(s.lockDim)], startPoint: .center, endPoint: .bottom) }
            if s.lyricBackground == 1 {
                AsyncImage(url: t?.artworkURL) { $0.resizable().scaledToFill().blur(radius: 70).opacity(0.7) } placeholder: { Color.clear }
                    .ignoresSafeArea()
            }
            if s.starsOn && s.lyricBackground != 1 { StarField().opacity(0.8) }
            VStack(spacing: 14) {
                Spacer()
                if !compact && (s.lockStage == 0 || (s.lockStage == 2 && s.lockRecordOn)) {
                    LockRecord(url: t?.artworkURL, size: s.lockRecordSize).padding(.bottom, 10)
                }
                if !compact && s.lockStage == 1 {
                    AsyncImage(url: t?.artworkURL) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.3) }
                        .frame(width: 380, height: 380).clipShape(RoundedRectangle(cornerRadius: 24)).shadow(radius: 30)
                }
                if compact || s.lockStage == 2 {
                    block(t, i, cur).scaleEffect(s.lyricScale).rotationEffect(.degrees(s.lyricLean))
                        .colorMultiply(s.lyricColorMode == 0 ? Color.white : lyricColour)
                }
                if s.lyricStyle != 2 && s.lockNextLineOn && (compact || s.lockStage == 2) {
                    Text(text((i ?? -1) + 1)).font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                }
                if let t, s.lockTitleOn { Text("\(t.title) · \(t.artist)").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6)) }
            }
            .padding(.horizontal, compact ? 20 : 80).padding(.bottom, compact ? 0 : 80)
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: i)
        }
        .ignoresSafeArea()
        .onChange(of: i) { _, _ in burst += 1 }
        .task(id: player.track?.artworkURL) { if let c = await AlbumColor.from(player.track?.artworkURL) { albumTint = c } }
    }

    @ViewBuilder private func block(_ t: Track?, _ i: Int?, _ cur: String) -> some View {
        switch s.lyricStyle {
        case 1:  bigWords(t, i)
        case 2:  lens(i)
        case 3:  terminal(t, i, cur)
        case 4:  aura(i, cur)
        default: stars(i, cur)
        }
    }

    // Aura: soft glowing words, colour from the cover
    private func aura(_ i: Int?, _ cur: String) -> some View {
        Text(cur).font(.system(size: 50, weight: .bold, design: .rounded)).foregroundStyle(.white)
            .shadow(color: .white.opacity(0.4), radius: 30).multilineTextAlignment(.center)
            .lineLimit(3).minimumScaleFactor(0.5).id(i ?? -1)
            .transition(.opacity.combined(with: .scale(scale: 1.05)))
    }

    // Stars: whole line scales in, sparkles burst outward
    private func stars(_ i: Int?, _ cur: String) -> some View {
        ZStack {
            StarBurst().id(burst)
            Text(cur).font(.system(size: 46, weight: .heavy, design: .rounded))
                .foregroundStyle(.white).shadow(color: .white.opacity(0.6), radius: 14)
                .multilineTextAlignment(.center).minimumScaleFactor(0.5).lineLimit(2)
                .id(i ?? -1)
                .transition(.asymmetric(insertion: .scale(scale: 0.85).combined(with: .opacity), removal: .opacity))
        }
    }

    // Big Words: one huge word at a time, paced across the line
    private func bigWords(_ t: Track?, _ i: Int?) -> some View {
        let words = text(i ?? -1).split(separator: " ").map(String.init)
        let k = words.isEmpty ? 0 : Int(progress(t, i) * Double(words.count))
        let word = words.isEmpty ? "♪" : words[min(k, words.count - 1)]
        return Text(word).font(.system(size: 110, weight: .black, design: .rounded))
            .foregroundStyle(.white).shadow(color: .white.opacity(0.5), radius: 16)
            .minimumScaleFactor(0.4).lineLimit(1)
            .offset(x: CGFloat((k * 73) % 100 - 50) * s.lyricScatter * 3, y: CGFloat((k * 41) % 100 - 50) * s.lyricScatter * 1.2)
            .id((i ?? -1) * 1000 + k)
            .transition(.asymmetric(insertion: .scale(scale: 1.3).combined(with: .opacity), removal: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: k)
    }

    // Lens: the current line is sharp; neighbouring lines fade and blur away
    private func lens(_ i: Int?) -> some View {
        let idx = i ?? -1
        return VStack(spacing: 10) {
            ForEach(-2...2, id: \.self) { d in
                Text(text(idx + d)).lineLimit(1).minimumScaleFactor(0.5)
                    .font(.system(size: d == 0 ? 42 : 24, weight: d == 0 ? .heavy : .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(d == 0 ? 1 : 0.55 - Double(abs(d)) * 0.15))
                    .blur(radius: CGFloat(abs(d)) * 2.5)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: idx)
    }

    // Terminal: green text typed out with a blinking cursor
    private func terminal(_ t: Track?, _ i: Int?, _ cur: String) -> some View {
        let n = Int(Double(cur.count) * min(1, progress(t, i) * 1.6))
        return TimelineView(.periodic(from: .now, by: 0.5)) { tl in
            let on = Int(tl.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            Text("> " + String(cur.prefix(n)) + (on ? "▌" : " "))
                .font(.system(size: 30, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.green).shadow(color: .green.opacity(0.7), radius: 8)
                .lineLimit(2).multilineTextAlignment(.leading)
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
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.interpolationQuality = .medium
            ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let r = Double(px[0]) / 255, g = Double(px[1]) / 255, b = Double(px[2]) / 255
        let m = max(r, g, b, 1.0 / 255)
        return Color(red: r / m, green: g / m, blue: b / m)
    }
}
