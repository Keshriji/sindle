import SwiftUI
import AppKit
import Foundation

/// The three lock-screen looks, in the order Needle moves through them.
enum LockMode: Int, CaseIterable {
    case record, cover, lyrics
}

/// Needle's lock layout in its own units: every x, y and size is a percentage of the screen width
/// (1 unit = 1% of the width), exactly like the lock screen demo on needlemac.com. That keeps the
/// record under the clock, the card below it, and the cover/lyrics split the same on every screen.
struct LockMetrics {
    let size: CGSize
    var u: CGFloat { size.width / 100 }

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: x * u, y: y * u, width: w * u, height: h * u)
    }

    func record(_ m: LockMode) -> CGRect {
        switch m {
        case .record: return rect(44.9, 29.9, 10.2, 10.2)
        case .cover:  return rect(40.6, 44.8, 3.0, 3.0)
        case .lyrics: return rect(18.4, 47.6, 2.7, 2.7)
        }
    }

    func cover(_ m: LockMode) -> CGRect {
        switch m {
        case .record: return rect(40.2, 42.9, 3.2, 3.2)
        case .cover:  return rect(40.7, 23.2, 18.6, 18.6)
        case .lyrics: return rect(13.7, 19.6, 25.8, 25.8)
        }
    }

    func card(_ m: LockMode) -> CGRect {
        switch m {
        case .record: return rect(39.3, 42.2, 21.3, 8.0)
        case .cover:  return rect(39.7, 44.0, 20.5, 7.8)
        case .lyrics: return rect(17.6, 47.0, 18.0, 7.2)
        }
    }

    func lyrics(_ m: LockMode) -> CGRect { rect(51.4, 19.6, 27.0, 34.0) }

    func coverRadius(_ m: LockMode) -> CGFloat {
        switch m {
        case .record: return 0.4 * u
        case .cover:  return 1.4 * u
        case .lyrics: return 1.5 * u
        }
    }

    func paddings(_ m: LockMode) -> (top: CGFloat, side: CGFloat, bottom: CGFloat) {
        if m == .lyrics { return (0.6 * u, 0.8 * u, 0.65 * u) }
        return (0.75 * u, 0.85 * u, 0.8 * u)
    }

    func slot(_ m: LockMode) -> CGFloat { m == .lyrics ? 2.7 * u : 3.2 * u }

    func controlsCenter(_ m: LockMode) -> CGPoint {
        let c = card(m)
        let p = paddings(m)
        return CGPoint(x: c.midX, y: c.maxY - p.bottom - 0.65 * u)
    }

    func controlCenters(_ m: LockMode) -> [CGPoint] {
        let c = controlsCenter(m)
        let gap = 3.6 * u
        return [CGPoint(x: c.x - gap, y: c.y), c, CGPoint(x: c.x + gap, y: c.y)]
    }
}

/// A hit on the art or card while the Mac is locked. The panel itself is click-through, so the
/// controller watches mouse-downs globally and converts them with the same metrics the view uses.
enum LockHit { case advance, previous, playpause, next, none }

func lockHit(_ p: CGPoint, _ m: LockMetrics, _ mode: LockMode, controls: Bool) -> LockHit {
    if controls {
        let centers = m.controlCenters(mode)
        let r = 2.0 * m.u
        for (i, c) in centers.enumerated() where abs(p.x - c.x) <= r && abs(p.y - c.y) <= r {
            switch i {
            case 0: return .previous
            case 1: return .playpause
            default: return .next
            }
        }
    }
    if m.cover(mode).insetBy(dx: -8, dy: -8).contains(p) { return .advance }
    if mode == .record, m.record(mode).insetBy(dx: -8, dy: -8).contains(p) { return .advance }
    let card = m.card(mode)
    if card.contains(p), p.y < card.minY + card.height * 0.55 { return .advance }
    return .none
}

// MARK: - screen

struct LockScreenView: View {
    @ObservedObject var player: NowPlaying
    @ObservedObject var lyrics: LyricsStore
    @ObservedObject var s = SettingsStore.shared
    @State private var tint = Color.white
    @State private var burst = 0

    init(player: NowPlaying, lyrics: LyricsStore) {
        self.player = player
        self.lyrics = lyrics
    }

    private var mode: LockMode { LockMode(rawValue: s.lockStage) ?? .lyrics }
    private var track: Track? { player.track }
    private var lineIndex: Int? { track.flatMap { lyrics.index(at: $0.position) } }

    var body: some View {
        GeometryReader { geo in
            let m = LockMetrics(size: geo.size)
            let mode = self.mode
            ZStack(alignment: .topLeading) {
                backdrop(m, mode)
                card(m, mode)
                record(m, mode)
                cover(m, mode)
                lyricsColumn(m, mode)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .task(id: track?.artworkURL) {
            if let c = await AlbumColor.from(track?.artworkURL) { tint = c }
        }
        .onChange(of: lineIndex) { _, _ in burst += 1 }
    }

    @ViewBuilder
    private func backdrop(_ m: LockMetrics, _ mode: LockMode) -> some View {
        ZStack {
            AsyncImage(url: track?.artworkURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.clear
            }
            .frame(width: m.size.width * 1.12, height: m.size.height * 1.12)
            .blur(radius: 3.2 * m.u)
            .brightness(-0.38)
            .position(x: m.size.width / 2, y: m.size.height / 2)
            .opacity(mode == .record ? 0 : 1)
            .animation(.easeInOut(duration: 1.6), value: mode)

            if s.starsOn && mode == .lyrics {
                StarField().opacity(0.7)
            }
            Color.black.opacity(0.30 + s.lockDim * 0.2)
        }
        .frame(width: m.size.width, height: m.size.height)
        .clipped()
    }

    private func card(_ m: LockMetrics, _ mode: LockMode) -> some View {
        let r = m.card(mode)
        return LockCard(player: player, size: r.size, u: m.u, mode: mode,
                        titleOn: s.lockTitleOn, controlsOn: s.lockControlsOn,
                        onAdvance: { advance() })
            .offset(x: r.minX, y: r.minY)
            .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.8), value: mode)
    }

    @ViewBuilder
    private func record(_ m: LockMetrics, _ mode: LockMode) -> some View {
        if mode == .record || s.lockRecordOn {
            let r = recordRect(m, mode)
            SpinningRecord(url: track?.artworkURL, size: r.width, playing: track?.isPlaying ?? false)
                .shadow(color: .black.opacity(0.4), radius: 0.8 * m.u, y: 0.4 * m.u)
                .offset(x: r.minX, y: r.minY)
                .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.8), value: mode)
                .onTapGesture { advance() }
        }
    }

    private func recordRect(_ m: LockMetrics, _ mode: LockMode) -> CGRect {
        let base = m.record(mode)
        guard mode == .record else { return base }
        let scale = min(max(CGFloat(s.lockRecordSize / 160), 0.6), 1.4)
        let w = base.width * scale
        let h = base.height * scale
        return CGRect(x: base.midX - w / 2, y: base.midY - h / 2, width: w, height: h)
    }

    private func cover(_ m: LockMetrics, _ mode: LockMode) -> some View {
        let r = m.cover(mode)
        let radius = m.coverRadius(mode)
        return CoverArt(url: track?.artworkURL)
            .frame(width: r.width, height: r.height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(mode == .record ? 0.2 : 0.35),
                    radius: mode == .record ? 0.2 * m.u : 1.4 * m.u,
                    y: 0.4 * m.u)
            .offset(x: r.minX, y: r.minY)
            .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.8), value: mode)
            .contentShape(Rectangle())
            .onTapGesture { advance() }
    }

    private func lyricsColumn(_ m: LockMetrics, _ mode: LockMode) -> some View {
        let r = m.lyrics(mode)
        return LockScreenLyrics(lyrics: lyrics, track: track, size: r.size, u: m.u,
                                style: s.lyricStyle, tint: tint, colorMode: s.lyricColorMode,
                                custom: Color(red: s.lyricR, green: s.lyricG, blue: s.lyricB),
                                nextOn: s.lockNextLineOn, scatter: s.lyricScatter, burst: burst)
            .frame(width: r.width, height: r.height)
            .offset(x: r.minX, y: r.minY)
            .opacity(mode == .lyrics ? 1 : 0)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.5).delay(mode == .lyrics ? 0.25 : 0), value: mode)
    }

    private func advance() {
        let next = LockMode(rawValue: (mode.rawValue + 1) % 3) ?? .record
        withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.8)) {
            s.lockStage = next.rawValue
        }
    }
}

// MARK: - card

struct LockCard: View {
    @ObservedObject var player: NowPlaying
    let size: CGSize
    let u: CGFloat
    let mode: LockMode
    let titleOn: Bool
    let controlsOn: Bool
    var onAdvance: () -> Void

    private var track: Track? { player.track }
    private var pad: (top: CGFloat, side: CGFloat, bottom: CGFloat) {
        if mode == .lyrics { return (0.6 * u, 0.8 * u, 0.65 * u) }
        return (0.75 * u, 0.85 * u, 0.8 * u)
    }
    private var slot: CGFloat { mode == .lyrics ? 2.7 * u : 3.2 * u }
    private var progress: Double {
        guard let t = track, t.duration > 0 else { return 0 }
        return min(max(t.position / t.duration, 0), 1)
    }
    private var cardTitle: String {
        let title = track?.title ?? ""
        return title.isEmpty ? "Nothing playing" : title
    }
    private var elapsed: String { fmt(track?.position ?? 0) }
    private var remaining: String {
        "-" + fmt(max(0, (track?.duration ?? 0) - (track?.position ?? 0)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow.frame(height: slot)
            Spacer(minLength: 0)
            progressRow.frame(height: 0.9 * u)
            Spacer(minLength: 0)
            if controlsOn { controls.frame(height: 1.3 * u) }
        }
        .padding(EdgeInsets(top: pad.top, leading: pad.side, bottom: pad.bottom, trailing: pad.side))
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(cardBackground)
    }

    private var topRow: some View {
        HStack(spacing: 0.8 * u) {
            Color.clear.frame(width: slot, height: slot)
            if titleOn {
                VStack(alignment: .leading, spacing: 0.18 * u) {
                    Text(cardTitle)
                        .font(.system(size: 1.02 * u, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(track?.artist ?? "")
                        .font(.system(size: 0.88 * u))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onAdvance() }
    }

    private var progressRow: some View {
        HStack(spacing: 0.55 * u) {
            Text(elapsed).frame(width: 2.1 * u, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule().fill(.white.opacity(0.92))
                        .frame(width: geo.size.width * CGFloat(progress))
                }
            }
            .frame(height: 0.24 * u)
            Text(remaining).frame(width: 2.1 * u, alignment: .trailing)
        }
        .font(.system(size: 0.66 * u, weight: .medium).monospacedDigit())
        .foregroundStyle(.white.opacity(0.6))
        .animation(.linear(duration: 1), value: progress)
    }

    private var controls: some View {
        ZStack {
            HStack(spacing: 2.4 * u) {
                button("backward.fill", "previous track")
                button(player.track?.isPlaying == true ? "pause.fill" : "play.fill", "playpause")
                button("forward.fill", "next track")
            }
            HStack {
                Spacer()
                Image(systemName: "airplayaudio")
                    .font(.system(size: 1.05 * u))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private func button(_ icon: String, _ cmd: String) -> some View {
        Button { player.send(cmd) } label: {
            Image(systemName: icon)
                .font(.system(size: 1.2 * u, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 1.2 * u, height: 1.2 * u)
        }
        .buttonStyle(.plain)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 1.3 * u, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 1.3 * u, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.17), .white.opacity(0.11)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 1.3 * u, style: .continuous)
                .strokeBorder(.white.opacity(0.13), lineWidth: 1))
            .overlay(RoundedRectangle(cornerRadius: 1.3 * u, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .clear],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 0.6 * u, y: 0.3 * u)
    }

    private func fmt(_ value: Double) -> String {
        let v = max(0, Int(value.rounded()))
        return String(format: "%d:%02d", v / 60, v % 60)
    }
}

// MARK: - cover

struct CoverArt: View {
    let url: URL?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    LinearGradient(colors: [Color(white: 0.25), Color(white: 0.12)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()

                LinearGradient(colors: [.clear, .white.opacity(0.13), .clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .blendMode(.screen)
                RadialGradient(colors: [.white.opacity(0.20), .clear],
                               center: .topLeading, startRadius: 0,
                               endRadius: max(geo.size.width, geo.size.height) * 0.8)
                    .blendMode(.screen)
                LinearGradient(colors: [.white.opacity(0.07), .clear],
                               startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.30))
                    .blendMode(.screen)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - record

struct SpinningRecord: View {
    let url: URL?
    let size: CGFloat
    let playing: Bool
    @State private var base = 0.0
    @State private var anchor = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { tl in
            let elapsed = tl.date.timeIntervalSince(anchor)
            let angle = playing ? (base + elapsed * 100).truncatingRemainder(dividingBy: 360) : base
            disc.rotationEffect(.degrees(angle))
        }
        .frame(width: size, height: size)
        .onChange(of: playing) { _, p in
            if p {
                anchor = Date()
            } else {
                base = (base + Date().timeIntervalSince(anchor) * 100).truncatingRemainder(dividingBy: 360)
            }
        }
    }

    private var disc: some View {
        ZStack {
            Circle().fill(Color(red: 0.055, green: 0.05, blue: 0.05))
            ForEach(0..<26, id: \.self) { i in
                Circle()
                    .stroke(Color.white.opacity(0.035), lineWidth: 0.5)
                    .frame(width: size * (0.32 + CGFloat(i) * 0.026))
            }
            Circle().fill(AngularGradient(colors: [.white.opacity(0.10), .clear, .white.opacity(0.05),
                                                   .clear, .white.opacity(0.10)], center: .center))
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color(white: 0.25)
            }
            .frame(width: size * 0.34, height: size * 0.34)
            .clipShape(Circle())
            Circle().fill(.black).frame(width: size * 0.045)
            Circle().stroke(.white.opacity(0.08), lineWidth: 0.8)
                .frame(width: max(0, size - 1), height: max(0, size - 1))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

// MARK: - lyrics column

struct LockScreenLyrics: View {
    @ObservedObject var lyrics: LyricsStore
    let track: Track?
    let size: CGSize
    let u: CGFloat
    let style: Int
    let tint: Color
    let colorMode: Int
    let custom: Color
    let nextOn: Bool
    let scatter: Double
    let burst: Int

    private var idx: Int? { track.flatMap { lyrics.index(at: $0.position) } }
    private var lineHeight: CGFloat { 1.78 * u * 1.22 + 2 * 1.15 * u }
    private var current: String { text(idx ?? -1) }

    var body: some View {
        Group {
            if lyrics.lines.isEmpty {
                Text("No synced lyrics found")
                    .font(.system(size: 1.4 * u, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch style {
                case 1: bigWords
                case 2: lens
                case 3: terminal
                case 4: aura
                default: stars
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private func text(_ i: Int) -> String {
        guard i >= 0, i < lyrics.lines.count else { return "" }
        return lyrics.lines[i].s
    }

    private var currentColour: Color {
        switch colorMode {
        case 1: return tint
        case 2: return custom
        default: return .white
        }
    }

    private func colour(_ i: Int) -> Color {
        if let idx, i == idx { return currentColour }
        return .white.opacity(nextOn ? 0.36 : 0.12)
    }

    private var progress: Double {
        guard let t = track, let i = idx, i < lyrics.lines.count else { return 0 }
        let start = lyrics.lines[i].t
        let end = i + 1 < lyrics.lines.count ? lyrics.lines[i + 1].t : start + 4
        return max(0, min(0.999, (t.position - start) / max(end - start, 0.5)))
    }

    private var stars: some View {
        ZStack {
            scrolling
            LockBurst(u: u).id(burst).allowsHitTesting(false)
        }
        .mask(LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: 0.16),
            .init(color: .black, location: 0.84),
            .init(color: .clear, location: 1)
        ], startPoint: .top, endPoint: .bottom))
    }

    private var scrolling: some View {
        VStack(spacing: 0) {
            ForEach(lyrics.lines.indices, id: \.self) { i in
                Text(text(i).isEmpty ? "♪" : text(i))
                    .font(.system(size: 1.78 * u, weight: .bold))
                    .foregroundStyle(colour(i))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(width: size.width, height: lineHeight, alignment: .leading)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .offset(y: size.height / 2 - (CGFloat(idx ?? 0) * lineHeight + lineHeight / 2))
        .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.9), value: idx)
    }

    private var bigWords: some View {
        let words = current.split(separator: " ").map(String.init)
        let k = words.isEmpty ? 0 : min(words.count - 1, Int(progress * Double(words.count)))
        let word = words.isEmpty ? "♪" : words[k]
        return Text(word)
            .font(.system(size: 4.2 * u, weight: .black, design: .rounded))
            .foregroundStyle(currentColour)
            .shadow(color: .white.opacity(0.35), radius: 1.2 * u)
            .lineLimit(2)
            .minimumScaleFactor(0.3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .offset(x: CGFloat((k * 73) % 100 - 50) * CGFloat(scatter) * 0.12 * u,
                    y: CGFloat((k * 41) % 100 - 50) * CGFloat(scatter) * 0.05 * u)
            .id((idx ?? -1) * 1000 + k)
            .transition(.asymmetric(insertion: .scale(scale: 1.25).combined(with: .opacity), removal: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: k)
    }

    private var lens: some View {
        VStack(spacing: 0.7 * u) {
            ForEach(-2...2, id: \.self) { d in
                Text(text((idx ?? -1) + d).isEmpty ? " " : text((idx ?? -1) + d))
                    .font(.system(size: (d == 0 ? 3.2 : 1.8) * u,
                                  weight: d == 0 ? .heavy : .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(d == 0 ? 1 : 0.55 - Double(abs(d)) * 0.15))
                    .blur(radius: CGFloat(abs(d)) * 0.2 * u)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: idx)
    }

    private var terminal: some View {
        let count = current.count
        let n = Int(Double(count) * min(1, progress * 1.6))
        return TimelineView(.periodic(from: .now, by: 0.5)) { tl in
            let on = Int(tl.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            Text("> " + String(current.prefix(n)) + (on ? "▌" : " "))
                .font(.system(size: 2.2 * u, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.green)
                .shadow(color: .green.opacity(0.7), radius: 0.6 * u)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var aura: some View {
        Text(current.isEmpty ? "♪" : current)
            .font(.system(size: 3.6 * u, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: currentColour.opacity(0.4), radius: 2.4 * u)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .id(idx ?? -1)
            .transition(.opacity.combined(with: .scale(scale: 1.05)))
    }
}

struct LockBurst: View {
    let u: CGFloat
    @State private var go = false

    var body: some View {
        ZStack {
            ForEach(0..<14, id: \.self) { i in
                let a = Double(i) / 14 * 2 * Double.pi
                Image(systemName: "sparkle")
                    .font(.system(size: (0.9 + CGFloat(i % 3) * 0.35) * u))
                    .foregroundStyle(i % 2 == 0 ? Color.yellow : Color.white)
                    .offset(x: go ? CGFloat(cos(a)) * 14 * u : 0,
                            y: go ? CGFloat(sin(a)) * 7 * u : 0)
                    .scaleEffect(go ? 0.3 : 1)
                    .opacity(go ? 0 : 1)
            }
        }
        .onAppear { withAnimation(.easeOut(duration: 1.1)) { go = true } }
    }
}
