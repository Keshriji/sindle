import SwiftUI
import AppKit

// Lock screen effects, drawn from scratch:
//  - Aura: one huge word at a time on a turning drum, over a dark heart ringed with the cover's colour.
//  - Stars: the song's words join into a growing network, the current word marked with a ring.
//  - Beat glow: a neon line that traces the whole screen edge, notch included, and pulses with the music.

// MARK: - shared helpers

/// Tiny copies of the album cover. Scaled up, a 24-pixel image is already a smooth blur, so no blur pass is
/// needed (a blur over a full screen, redrawn every frame, is what makes a lock screen hitch).
final class SoftCover: ObservableObject {
    @Published var far: NSImage?
    @Published var near: NSImage?
    private var loaded: URL?

    func load(_ url: URL?) async {
        guard let url else { return }
        let already: Bool = await MainActor.run { self.loaded == url }
        if already { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        await MainActor.run {
            guard let img = NSImage(data: data) else { return }
            self.loaded = url
            self.far = Self.shrink(img, to: 24)
            self.near = Self.shrink(img, to: 96)
        }
    }

    private static func shrink(_ img: NSImage, to side: CGFloat) -> NSImage {
        let out = NSImage(size: NSSize(width: side, height: side))
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        img.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
    }
}

/// A word or short phrase and the moment it starts being sung.
struct AuraChunk: Identifiable {
    let id: Int
    let text: String
    let start: Double
}

enum AuraTimeline {
    /// Splits every line into chunks and spreads their start times across the line, weighted by length.
    /// With `pairing`, a short word (three letters or fewer) rides along with the word after it.
    static func build(_ lines: [LyricLine], pairing: Bool) -> [AuraChunk] {
        var out: [AuraChunk] = []
        for (i, line) in lines.enumerated() {
            let words = line.s.split(separator: " ").map(String.init)
            if words.isEmpty { continue }
            var groups: [[String]] = []
            var k = 0
            while k < words.count {
                let w = words[k]
                let letters = w.filter { $0.isLetter }.count
                if pairing && letters <= 3 && k + 1 < words.count {
                    groups.append([w, words[k + 1]])
                    k += 2
                } else {
                    groups.append([w])
                    k += 1
                }
            }
            let start = line.t
            let end = i + 1 < lines.count ? lines[i + 1].t : start + 4
            let span = max(0.6, (end - start) * 0.92)
            let weights: [Double] = groups.map { Double(max($0.joined(separator: " ").count, 2)) }
            let total = weights.reduce(0, +)
            var acc = 0.0
            for (g, grp) in groups.enumerated() {
                out.append(AuraChunk(id: out.count, text: grp.joined(separator: " "), start: start + span * acc / total))
                acc += weights[g]
            }
        }
        return out
    }

    /// Index of the last chunk that has started by `pos`, or -1 before the first one.
    static func current(_ chunks: [AuraChunk], at pos: Double) -> Int {
        var lo = 0
        var hi = chunks.count - 1
        var answer = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if chunks[mid].start <= pos {
                answer = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return answer
    }
}

/// Where the song is right now, in seconds: the last reading, plus the time since, plus the timing offset.
func lockLivePos(_ t: Track?, _ now: Date = Date()) -> Double {
    guard let t else { return 0 }
    let since: Double = t.isPlaying ? now.timeIntervalSince(t.polledAt) : 0
    return t.position + since + SettingsStore.shared.lyricOffset
}

// MARK: - Aura: backdrop

/// A dark heart that breathes with the music, ringed by the cover's own colours, with a lit rim at the edge.
struct AuraBackdrop: View {
    let url: URL?
    let tint: Color
    let audio: AudioLevel
    @StateObject private var soft = SoftCover()

    var body: some View {
        GeometryReader { g in
            TimelineView(.periodic(from: .now, by: 1.0 / 20.0)) { tl in
                let t: Double = tl.date.timeIntervalSinceReferenceDate
                let live: Bool = tl.date.timeIntervalSince(audio.lastSample) < 1.5
                let level: Double = live ? audio.level : 0.35 + 0.15 * sin(t * 1.3)
                let w: CGFloat = g.size.width
                let h: CGFloat = g.size.height
                let heart: CGFloat = min(w, h) * CGFloat(0.5 + 0.12 * level)
                let sway: CGFloat = CGFloat(sin(t * 0.21)) * w * 0.03
                let bob: CGFloat = CGFloat(cos(t * 0.17)) * h * 0.03
                ZStack {
                    Color.black
                    if let img = soft.far {
                        Image(nsImage: img).resizable().interpolation(.high).scaledToFill()
                            .frame(width: w * 1.15, height: h * 1.15)
                            .saturation(1.6)
                    } else {
                        tint.opacity(0.4)
                    }
                    RadialGradient(colors: [.black, .black.opacity(0.92), .black.opacity(0)],
                                   center: .center, startRadius: 0, endRadius: heart)
                        .scaleEffect(x: 1.55, y: 0.95)
                        .offset(x: sway, y: bob)
                    RadialGradient(colors: [.clear, .white.opacity(0.0), .white.opacity(0.26)],
                                   center: .center, startRadius: min(w, h) * 0.55, endRadius: max(w, h) * 0.75)
                }
                .frame(width: w, height: h)
                .clipped()
            }
        }
        .task(id: url) { await soft.load(url) }
    }
}

// MARK: - Aura: the word drum

/// Places one word on the drum. `d` is how many words it is from the front: at 0 it is huge and flat to the
/// screen, further round it shrinks, tilts, blurs while the drum is turning, and past the top it shows its
/// mirrored back. Because the modifier is Animatable, the whole turn is driven smoothly by `cursor`.
struct DrumWord: ViewModifier, Animatable {
    var cursor: Double
    let index: Double
    let spread: CGFloat

    var animatableData: Double {
        get { cursor }
        set { cursor = newValue }
    }

    func body(content: Content) -> some View {
        let d: Double = index - cursor
        let a: Double = abs(d)
        let angle: Double = d * 42.0
        let scale: CGFloat = CGFloat(1.0 / (1.0 + 1.7 * a))
        let fade: Double = a < 2.6 ? max(0.0, 1.0 - 0.42 * a) : 0.0
        let motion: CGFloat = CGFloat(abs(d - d.rounded()) * 16.0)
        let y: CGFloat = CGFloat(sin(d * 0.62)) * spread
        return content
            .scaleEffect(scale)
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
            .offset(y: y)
            .blur(radius: motion)
            .opacity(fade)
    }
}

struct AuraDrum: View {
    @ObservedObject var lyrics: LyricsStore
    let track: Track?
    let colour: Color
    let size: CGSize
    @State private var chunks: [AuraChunk] = []
    @State private var cursor: Double = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.08)) { _ in
            let cur: Int = AuraTimeline.current(chunks, at: lockLivePos(track))
            ZStack {
                if chunks.isEmpty {
                    Text("No synced lyrics found")
                        .font(.system(size: size.height * 0.04, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                } else {
                    ForEach(window(cur)) { c in word(c) }
                }
            }
            .frame(width: size.width, height: size.height)
            .onChange(of: cur) { _, n in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.76)) { cursor = Double(n) }
            }
        }
        .onAppear {
            chunks = AuraTimeline.build(lyrics.lines, pairing: true)
            cursor = Double(AuraTimeline.current(chunks, at: lockLivePos(track)))
        }
        .onChange(of: lyrics.lines) { _, new in chunks = AuraTimeline.build(new, pairing: true) }
    }

    /// The few chunks around the front of the drum: the rest are invisible anyway.
    private func window(_ cur: Int) -> [AuraChunk] {
        guard !chunks.isEmpty else { return [] }
        let lo = max(0, cur - 3)
        let hi = min(chunks.count - 1, max(cur, 0) + 4)
        guard lo <= hi else { return [] }
        return Array(chunks[lo...hi])
    }

    private func word(_ c: AuraChunk) -> some View {
        let chars: CGFloat = CGFloat(max(c.text.count, 2))
        let byWidth: CGFloat = size.width * 0.8 / (chars * 0.56)
        let fs: CGFloat = min(size.height * 0.30, byWidth)
        return Text(c.text)
            .font(.system(size: fs, weight: .black))
            .tracking(-fs * 0.045)
            .foregroundStyle(colour)
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .frame(width: size.width * 0.9)
            .shadow(color: .black.opacity(0.35), radius: fs * 0.06, y: fs * 0.04)
            .modifier(DrumWord(cursor: cursor, index: Double(c.id), spread: size.height * 0.42))
    }
}

// MARK: - Stars: smoky backdrop

/// The cover turned into slow black-and-white smoke, a pool of light at the top and drifting specks.
struct SmokyBackdrop: View {
    let url: URL?
    @StateObject private var soft = SoftCover()

    var body: some View {
        GeometryReader { g in
            TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { tl in
                let t: Double = tl.date.timeIntervalSinceReferenceDate
                let w: CGFloat = g.size.width
                let h: CGFloat = g.size.height
                let breathe: CGFloat = 1.0 + 0.03 * CGFloat(sin(t * 0.13))
                ZStack {
                    Color.black
                    if let near = soft.near {
                        Image(nsImage: near).resizable().interpolation(.high).scaledToFill()
                            .frame(width: w * 1.2, height: h * 1.2)
                            .saturation(0).contrast(1.35).brightness(-0.12)
                            .scaleEffect(breathe)
                            .offset(x: CGFloat(sin(t * 0.09)) * w * 0.02, y: CGFloat(cos(t * 0.07)) * h * 0.02)
                            .opacity(0.8)
                        Image(nsImage: near).resizable().interpolation(.high).scaledToFill()
                            .frame(width: w * 1.5, height: h * 1.5)
                            .saturation(0).contrast(1.6)
                            .rotationEffect(.degrees(t * 0.6))
                            .blendMode(.plusLighter)
                            .opacity(0.16)
                    }
                    RadialGradient(colors: [.white.opacity(0.22), .clear], center: UnitPoint(x: 0.5, y: 0.1),
                                   startRadius: 0, endRadius: w * 0.35)
                    RadialGradient(colors: [.clear, .black.opacity(0.75)], center: .center,
                                   startRadius: w * 0.25, endRadius: w * 0.75)
                    Specks(t: t)
                }
                .frame(width: w, height: h)
                .clipped()
            }
        }
        .task(id: url) { await soft.load(url) }
    }
}

struct Specks: View {
    let t: Double
    private struct Dot { let x: Double, y: Double, vx: Double, vy: Double, r: Double, p: Double }
    private let dots: [Dot] = {
        var rng = SeededRNG(s: 42)
        return (0..<70).map { _ in
            Dot(x: Double.random(in: 0...1, using: &rng), y: Double.random(in: 0...1, using: &rng),
                vx: Double.random(in: -0.004...0.004, using: &rng), vy: Double.random(in: -0.003...0.003, using: &rng),
                r: Double.random(in: 0.6...2.0, using: &rng), p: Double.random(in: 0...6.28, using: &rng))
        }
    }()

    var body: some View {
        Canvas { ctx, size in
            for d in dots {
                let fx: Double = (d.x + d.vx * t).truncatingRemainder(dividingBy: 1)
                let fy: Double = (d.y + d.vy * t).truncatingRemainder(dividingBy: 1)
                let x: Double = (fx + 1).truncatingRemainder(dividingBy: 1)
                let y: Double = (fy + 1).truncatingRemainder(dividingBy: 1)
                ctx.opacity = 0.25 + 0.5 * (0.5 + 0.5 * sin(t * 1.4 + d.p))
                let rect = CGRect(x: x * Double(size.width), y: y * Double(size.height), width: d.r, height: d.r)
                ctx.fill(Path(ellipseIn: rect), with: .color(.white))
            }
        }
    }
}

// MARK: - Stars: the word network

/// Every word of the song becomes a point. Sixteen at a time are drawn, each joined to the one before (and
/// often to the one two or three back) so a mesh of thin lines grows as the song goes. The word being sung gets a
/// ring and a big label; when the sixteen are used up, a fresh network starts.
struct ConstellationGraph: View {
    @ObservedObject var lyrics: LyricsStore
    let track: Track?
    let audio: AudioLevel
    @State private var words: [AuraChunk] = []

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                draw(&ctx, size, tl.date)
            }
        }
        .onAppear { words = AuraTimeline.build(lyrics.lines, pairing: false) }
        .onChange(of: lyrics.lines) { _, new in words = AuraTimeline.build(new, pairing: false) }
    }

    private func mix(_ k: Int, _ seg: Int, _ m: Int) -> Int {
        let v: Int = (k &* 73856093) ^ (seg &* 19349663)
        return abs(v) % m
    }

    private func point(_ k: Int, _ seg: Int, _ band: CGRect) -> CGPoint {
        let n: Int = k - seg * 16
        var rng = SeededRNG(s: UInt64(truncatingIfNeeded: seg &* 7919 &+ k &* 104729 &+ 17))
        let fx: Double = Double(n) / 15.0 + Double.random(in: -0.045...0.045, using: &rng)
        let wave: Double = sin(Double(n) * 1.55 + Double(seg)) * 0.4
        let fy: Double = 0.5 + wave + Double.random(in: -0.12...0.12, using: &rng)
        let cx: Double = min(1, max(0, fx))
        let cy: Double = min(1, max(0, fy))
        return CGPoint(x: band.minX + band.width * CGFloat(cx), y: band.minY + band.height * CGFloat(cy))
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ date: Date) {
        guard !words.isEmpty, size.width > 10 else { return }
        let pos: Double = lockLivePos(track, date)
        let cur: Int = AuraTimeline.current(words, at: pos)
        guard cur >= 0 else { return }
        let seg: Int = cur / 16
        let first: Int = seg * 16
        let last: Int = min(cur, first + 15)
        let band = CGRect(x: size.width * 0.2, y: size.height * 0.40, width: size.width * 0.6, height: size.height * 0.30)
        let live: Bool = date.timeIntervalSince(audio.lastSample) < 1.5
        let level: Double = live ? audio.level : 0.3

        var pts: [CGPoint] = []
        for k in first...last { pts.append(point(k, seg, band)) }

        // the lines
        for n in 1..<max(pts.count, 1) {
            let k: Int = first + n
            let grow: Double = min(1, max(0, (pos - words[k].start) / 0.28))
            var links: [Int] = [n - 1]
            if n >= 2 && mix(k, seg, 3) != 0 { links.append(n - 2) }
            if n >= 3 && mix(k, seg, 5) == 0 { links.append(n - 3) }
            for l in links {
                let from: CGPoint = pts[l]
                let to: CGPoint = pts[n]
                let end = CGPoint(x: from.x + (to.x - from.x) * CGFloat(grow), y: from.y + (to.y - from.y) * CGFloat(grow))
                var p = Path()
                p.move(to: from)
                p.addLine(to: end)
                ctx.stroke(p, with: .color(.white.opacity(0.8)), lineWidth: 0.9)
            }
        }

        // the small dots and labels
        let small: CGFloat = size.width * 0.0105
        for n in 0..<pts.count {
            let k: Int = first + n
            if k == cur { continue }
            let fade: Double = min(1, max(0, (pos - words[k].start) / 0.2))
            let pt: CGPoint = pts[n]
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 1.6, y: pt.y - 1.6, width: 3.2, height: 3.2)),
                     with: .color(.white.opacity(0.9 * fade)))
            let label = Text(words[k].text).font(.system(size: small, weight: .semibold)).foregroundColor(.white.opacity(0.85 * fade))
            ctx.draw(label, at: CGPoint(x: pt.x + 4, y: pt.y + small * 0.9), anchor: .leading)
        }

        // the word being sung: a ring, a sparkle and a big label
        let c: CGPoint = pts[pts.count - 1]
        let radius: CGFloat = size.width * 0.012 * CGFloat(1.0 + 0.3 * level)
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)),
                   with: .color(.white), lineWidth: 1.4)
        for q in 0..<4 {
            let a: Double = Double(q) * Double.pi / 2
            let dx: CGFloat = CGFloat(cos(a))
            let dy: CGFloat = CGFloat(sin(a))
            var tick = Path()
            tick.move(to: CGPoint(x: c.x + dx * radius * 1.15, y: c.y + dy * radius * 1.15))
            tick.addLine(to: CGPoint(x: c.x + dx * radius * 1.6, y: c.y + dy * radius * 1.6))
            ctx.stroke(tick, with: .color(.white.opacity(0.9)), lineWidth: 1.2)
        }
        var star = Path()
        let tip: CGFloat = radius * 0.62
        let waist: CGFloat = radius * 0.14
        for q in 0..<8 {
            let a: Double = Double(q) * Double.pi / 4 - Double.pi / 2
            let r: CGFloat = q % 2 == 0 ? tip : waist
            let p = CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
            if q == 0 { star.move(to: p) } else { star.addLine(to: p) }
        }
        star.closeSubpath()
        ctx.fill(star, with: .color(.white))

        let big = Text(words[cur].text).font(.system(size: size.width * 0.036, weight: .black)).foregroundColor(.white)
        ctx.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.6), radius: 4))
            layer.draw(big, at: CGPoint(x: c.x + radius * 1.7, y: c.y + radius * 1.4), anchor: .topLeading)
        }
    }
}

/// The song title stacked down the left edge, one letter under another.
struct VerticalTitle: View {
    let text: String
    let colour: Color
    let width: CGFloat

    var body: some View {
        let letters: [Character] = Array(text.lowercased().filter { $0.isLetter || $0 == " " }.prefix(14))
        VStack(spacing: width * 0.004) {
            ForEach(0..<letters.count, id: \.self) { i in
                Text(letters[i] == " " ? " " : String(letters[i]))
                    .font(.system(size: width * 0.034, weight: .black, design: .serif))
                    .foregroundStyle(colour)
                    .shadow(color: colour.opacity(0.6), radius: 6)
            }
        }
    }
}

// MARK: - Beat glow along the screen edge

/// The outline of the display: rounded corners and, on a notched Mac, the notch.
struct ScreenOutline: Shape {
    let notchWidth: CGFloat      // 0 when there is no notch
    let notchDepth: CGFloat
    let corner: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = corner
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        if notchWidth > 0 {
            let nr: CGFloat = min(8, notchDepth / 3)
            let left: CGFloat = r.midX - notchWidth / 2
            let right: CGFloat = r.midX + notchWidth / 2
            p.addLine(to: CGPoint(x: left - nr, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: left, y: r.minY + nr), control: CGPoint(x: left, y: r.minY))
            p.addLine(to: CGPoint(x: left, y: r.minY + notchDepth - nr))
            p.addQuadCurve(to: CGPoint(x: left + nr, y: r.minY + notchDepth), control: CGPoint(x: left, y: r.minY + notchDepth))
            p.addLine(to: CGPoint(x: right - nr, y: r.minY + notchDepth))
            p.addQuadCurve(to: CGPoint(x: right, y: r.minY + notchDepth - nr), control: CGPoint(x: right, y: r.minY + notchDepth))
            p.addLine(to: CGPoint(x: right, y: r.minY + nr))
            p.addQuadCurve(to: CGPoint(x: right + nr, y: r.minY), control: CGPoint(x: right, y: r.minY))
        }
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + c), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addQuadCurve(to: CGPoint(x: r.maxX - c, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - c), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.addQuadCurve(to: CGPoint(x: r.minX + c, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

/// A neon line round the whole screen edge. Four strokes of growing width and falling brightness give the bloom
/// without any blur, a light that slowly chases round the outline, and a kick on every beat.
struct LockBeatGlow: View {
    let audio: AudioLevel
    let tint: Color
    let playing: Bool
    @ObservedObject var s = SettingsStore.shared

    private var notchW: CGFloat {
        guard let screen = NSScreen.main, screen.auxiliaryTopLeftArea != nil else { return 0 }
        return IslandPanel.notchWidth
    }
    private var notchD: CGFloat { NSScreen.main?.safeAreaInsets.top ?? 0 }

    private func colour(_ t: Double) -> Color {
        switch s.glowColorMode {
        case 1:  return Color(red: s.glowR, green: s.glowG, blue: s.glowB)
        case 2:  return Color(hue: (t * 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.85, brightness: 1)
        default: return tint
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { tl in
            let t: Double = tl.date.timeIntervalSinceReferenceDate
            let live: Bool = tl.date.timeIntervalSince(audio.lastSample) < 1.5
            let phase: Double = (t * s.glowBPM / 60).truncatingRemainder(dividingBy: 1)
            let kick: Double = live ? audio.level : exp(-4 * phase)
            let power: Double = playing ? (0.3 + 0.7 * kick) * s.glowIntensity : 0.12
            outline(power, t)
        }
        .allowsHitTesting(false)
    }

    private func outline(_ power: Double, _ t: Double) -> some View {
        let shape = ScreenOutline(notchWidth: notchW, notchDepth: notchD, corner: 12)
        let widths: [CGFloat] = [2, 6, 14, 28]
        let alphas: [Double] = [1.0, 0.5, 0.22, 0.10]
        let thick: CGFloat = CGFloat(0.6 + s.glowThickness / 10.0)
        let col: Color = colour(t)
        return ZStack {
            ForEach(0..<4, id: \.self) { i in
                shape.stroke(col.opacity(alphas[i] * power), lineWidth: widths[i] * thick)
            }
        }
        .blendMode(.plusLighter)
        .mask(
            AngularGradient(gradient: Gradient(colors: [.white, .white.opacity(0.4), .white, .white.opacity(0.3), .white]),
                            center: .center, angle: .degrees(t * 25))
        )
    }
}
