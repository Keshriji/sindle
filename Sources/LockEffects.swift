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

/// The colour of word number `index`, from the Settings choice: 0 white, 1 cover colour (bright), 2 custom, 3 rainbow.
func lyricColour(_ mode: Int, tint: Color, custom: Color, index: Int) -> Color {
    switch mode {
    case 1:  return vividColour(tint)
    case 2:  return custom
    case 3:  return Color(hue: Double(index % 12) / 12.0, saturation: 0.65, brightness: 1.0)
    default: return Color(white: 0.95)
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
    let colourFor: (Int) -> Color
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
            .foregroundStyle(colourFor(c.id))
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .frame(width: size.width * 0.9)
            .shadow(color: .black.opacity(0.35), radius: fs * 0.06, y: fs * 0.04)
            .modifier(DrumWord(cursor: cursor, index: Double(c.id), spread: size.height * 0.42))
    }
}

// MARK: - Stars: smoky backdrop

/// Remembers the last few zoom levels of the background, so older copies can be drawn trailing behind the newest.
final class BreathTrail {
    private var smooth: Double = 0
    var scales: [Double] = Array(repeating: 1.05, count: 7)

    /// Feeds in the music's loudness (fast rise, slow fall) and returns the smoothed value.
    func step(level: Double, slow: Double) -> Double {
        smooth = level > smooth ? level : smooth * 0.9 + level * 0.1
        let target: Double = 1.05 + 0.07 * smooth + 0.015 * slow
        scales.removeLast()
        scales.insert(target, at: 0)
        return smooth
    }
}

/// The cover's own colours, melted into soft glowing shapes on black, breathing with the music: the picture swells on
/// every beat and settles back, with older zoom levels trailing behind the newest like a motion blur. A pool of the
/// cover's brightest colour glows behind the clock and pulses with the sound; specks drift over everything.
struct SmokyBackdrop: View {
    let url: URL?
    let audio: AudioLevel
    let tint: Color
    @StateObject private var soft = SoftCover()
    @State private var trail = BreathTrail()
    private let ghostOpacity: [Double] = [0.85, 0.34, 0.2, 0.12]

    var body: some View {
        GeometryReader { g in
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { tl in
                let t: Double = tl.date.timeIntervalSinceReferenceDate
                let live: Bool = tl.date.timeIntervalSince(audio.lastSample) < 1.5
                let bass: Double = live ? max(audio.level, audio.bands[0]) : 0.35 + 0.35 * max(0.0, sin(t * 1.6))
                let level: Double = trail.step(level: bass, slow: sin(t * 0.9))
                let w: CGFloat = g.size.width
                let h: CGFloat = g.size.height
                ZStack {
                    Color.black
                    if let far = soft.far {
                        ForEach([3, 2, 1, 0], id: \.self) { i in
                            cover(far, w, h, scale: trail.scales[i * 2], opacity: ghostOpacity[i], t: t, level: level)
                        }
                    }
                    if let near = soft.near {
                        Image(nsImage: near).resizable().interpolation(.high).scaledToFill()
                            .frame(width: w * 1.5, height: h * 1.5)
                            .saturation(1.3)
                            .rotationEffect(.degrees(t * 0.6))
                            .blendMode(.plusLighter)
                            .opacity(0.14)
                    }
                    RadialGradient(colors: [tint.opacity(0.30 + 0.3 * level), .clear], center: UnitPoint(x: 0.5, y: 0.1),
                                   startRadius: 0, endRadius: w * 0.4)
                    RadialGradient(colors: [.clear, .black.opacity(0.78)], center: .center,
                                   startRadius: w * 0.22, endRadius: w * 0.75)
                    Specks(t: t)
                }
                .frame(width: w, height: h)
                .clipped()
            }
        }
        .task(id: url) { await soft.load(url) }
    }

    private func cover(_ img: NSImage, _ w: CGFloat, _ h: CGFloat, scale: Double, opacity: Double, t: Double, level: Double) -> some View {
        let sway: CGFloat = CGFloat(sin(t * 0.09)) * w * 0.02
        let bob: CGFloat = CGFloat(cos(t * 0.07)) * h * 0.02
        return Image(nsImage: img).resizable().interpolation(.high).scaledToFill()
            .frame(width: w * 1.2, height: h * 1.2)
            .saturation(1.25).brightness(-0.12 + 0.12 * level)
            .scaleEffect(CGFloat(scale))
            .rotationEffect(.degrees(sin(t * 0.05) * 1.5))
            .offset(x: sway, y: bob)
            .opacity(opacity)
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

/// Every word of the song becomes a point. Sixteen at a time are drawn, each joined to the one before and to several
/// earlier ones, so a dense mesh of thin lines grows as the song goes. Every point is a small sparkle with its word
/// beside it. The word being sung gets a ring that glides to it from the last word, and a big label. When the sixteen
/// are used up, the old network fades out as a fresh one begins.
struct ConstellationGraph: View {
    @ObservedObject var lyrics: LyricsStore
    let track: Track?
    let audio: AudioLevel
    let colourFor: (Int) -> Color
    var dim = false                  // true when drawn quietly behind Aura or Big Words
    @State private var words: [AuraChunk] = []

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { tl in
            Canvas { ctx, size in
                draw(&ctx, size, tl.date)
            }
        }
        .onAppear { words = AuraTimeline.build(lyrics.lines, pairing: false) }
        .onChange(of: lyrics.lines) { _, new in words = AuraTimeline.build(new, pairing: false) }
    }

    /// Smooth start and stop: 0...1 in, 0...1 out.
    private func ease(_ x: Double) -> Double {
        let t: Double = min(1, max(0, x))
        return t * t * (3 - 2 * t)
    }

    private func mix(_ k: Int, _ seg: Int, _ m: Int) -> Int {
        let v: Int = (k &* 73856093) ^ (seg &* 19349663)
        return abs(v) % m
    }

    private func point(_ k: Int, _ seg: Int, _ band: CGRect) -> CGPoint {
        let n: Int = k - seg * 16
        var rng = SeededRNG(s: UInt64(truncatingIfNeeded: seg &* 7919 &+ k &* 104729 &+ 17))
        let fx: Double = Double(n) / 15.0 + Double.random(in: -0.05...0.05, using: &rng)
        let wave: Double = sin(Double(n) * 1.55 + Double(seg)) * 0.42
        let fy: Double = 0.5 + wave + Double.random(in: -0.14...0.14, using: &rng)
        let cx: Double = min(1, max(0, fx))
        let cy: Double = min(1, max(0, fy))
        return CGPoint(x: band.minX + band.width * CGFloat(cx), y: band.minY + band.height * CGFloat(cy))
    }

    /// A four-point sparkle.
    private func sparkle(_ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        for q in 0..<8 {
            let a: Double = Double(q) * Double.pi / 4 - Double.pi / 2
            let rr: CGFloat = q % 2 == 0 ? r : r * 0.22
            let pt = CGPoint(x: c.x + CGFloat(cos(a)) * rr, y: c.y + CGFloat(sin(a)) * rr)
            if q == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ date: Date) {
        guard !words.isEmpty, size.width > 10 else { return }
        let pos: Double = lockLivePos(track, date)
        let cur: Int = AuraTimeline.current(words, at: pos)
        guard cur >= 0 else { return }
        let seg: Int = cur / 16
        let first: Int = seg * 16
        let band = CGRect(x: size.width * 0.08, y: size.height * 0.44, width: size.width * 0.84, height: size.height * 0.36)
        let live: Bool = date.timeIntervalSince(audio.lastSample) < 1.5
        let level: Double = live ? audio.level : 0.3

        // The network that just filled up fades away while the next one starts.
        let sinceSeg: Double = pos - words[first].start
        if seg > 0 && sinceSeg < 0.7 {
            drawSegment(&ctx, size, band, seg - 1, (seg - 1) * 16, first - 1, pos, alpha: 1 - ease(sinceSeg / 0.7), ring: false, level: level)
        }
        drawSegment(&ctx, size, band, seg, first, cur, pos, alpha: 1, ring: true, level: level)
    }

    private func drawSegment(_ ctx: inout GraphicsContext, _ size: CGSize, _ band: CGRect, _ seg: Int,
                             _ first: Int, _ last: Int, _ pos: Double, alpha: Double, ring: Bool, level: Double) {
        guard last >= first, last < words.count else { return }
        ctx.opacity = alpha
        var pts: [CGPoint] = []
        for k in first...last { pts.append(point(k, seg, band)) }

        // the thin lines, each growing out of the earlier point
        for n in 1..<max(pts.count, 1) {
            let k: Int = first + n
            let grow: Double = ease((pos - words[k].start) / 0.35)
            var links: [Int] = [n - 1]
            if n >= 2 && mix(k, seg, 4) != 0 { links.append(n - 2) }
            if n >= 3 && mix(k, seg, 2) == 0 { links.append(n - 3) }
            if n >= 4 && mix(k, seg, 5) == 0 { links.append(n - 4) }
            for l in links {
                let from: CGPoint = pts[l]
                let to: CGPoint = pts[n]
                let end = CGPoint(x: from.x + (to.x - from.x) * CGFloat(grow), y: from.y + (to.y - from.y) * CGFloat(grow))
                var p = Path()
                p.move(to: from)
                p.addLine(to: end)
                ctx.stroke(p, with: .color(colourFor(k).opacity(dim ? 0.3 : 0.75)), lineWidth: 0.9)
            }
        }

        // a sparkle and a small word at every point
        let small: CGFloat = size.width * 0.0115
        let spark: CGFloat = size.width * 0.0046
        for n in 0..<pts.count {
            let k: Int = first + n
            if ring && k == last { continue }                   // the current word is drawn below, bigger
            let fade: Double = ease((pos - words[k].start) / 0.3)
            let pt: CGPoint = pts[n]
            ctx.fill(sparkle(pt, spark * CGFloat(0.5 + 0.5 * fade)), with: .color(colourFor(k).opacity(0.95 * fade)))
            let label = Text(words[k].text).font(.system(size: small, weight: .semibold)).foregroundColor(colourFor(k).opacity(0.9 * fade))
            ctx.draw(label, at: CGPoint(x: pt.x + spark + 3, y: pt.y + small * 0.9), anchor: .leading)
        }

        guard ring else { ctx.opacity = 1; return }

        // the word being sung: a ring that glides in from the last word, a sparkle and a big label
        let idx: Int = pts.count - 1
        let arrive: Double = ease((pos - words[last].start) / 0.28)
        let from: CGPoint = idx > 0 ? pts[idx - 1] : pts[idx]
        let target: CGPoint = pts[idx]
        let c = CGPoint(x: from.x + (target.x - from.x) * CGFloat(arrive), y: from.y + (target.y - from.y) * CGFloat(arrive))
        let tone: Color = colourFor(last)
        let radius: CGFloat = size.width * 0.012 * CGFloat(1.0 + 0.3 * level)
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)),
                   with: .color(tone), lineWidth: 1.4)
        for q in 0..<4 {
            let a: Double = Double(q) * Double.pi / 2
            let dx: CGFloat = CGFloat(cos(a))
            let dy: CGFloat = CGFloat(sin(a))
            var tick = Path()
            tick.move(to: CGPoint(x: c.x + dx * radius * 1.15, y: c.y + dy * radius * 1.15))
            tick.addLine(to: CGPoint(x: c.x + dx * radius * 1.6, y: c.y + dy * radius * 1.6))
            ctx.stroke(tick, with: .color(tone.opacity(0.9)), lineWidth: 1.2)
        }
        ctx.fill(sparkle(c, radius * 0.66), with: .color(tone))

        if !dim {
            let big = Text(words[last].text).font(.system(size: size.width * 0.036, weight: .black)).foregroundColor(tone)
            let rise: CGFloat = CGFloat(1 - arrive) * radius * 0.8
            ctx.opacity = alpha * arrive
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: tone.opacity(0.7), radius: 8))
                layer.draw(big, at: CGPoint(x: c.x + radius * 1.7, y: c.y + radius * 1.4 + rise), anchor: .topLeading)
            }
        }
        ctx.opacity = 1
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
            let live: Bool = s.glowMotion == 0 && tl.date.timeIntervalSince(audio.lastSample) < 1.5
            let phase: Double = (t * s.glowBPM / 60).truncatingRemainder(dividingBy: 1)
            let kick: Double = live ? audio.level : exp(-4 * phase)
            let power: Double = playing ? (0.3 + 0.7 * kick) * s.glowIntensity : 0.12
            GlowRim(colour: colour(t), power: power, t: t, thick: CGFloat(0.6 + s.glowThickness / 10.0))
        }
        .allowsHitTesting(false)
    }
}

/// A neon line round the whole screen edge, notch included. Four strokes of growing width and falling brightness give
/// the bloom without any blur, a light slowly chases round the outline, and a thin hot core sits on top.
/// Used on the lock screen and on the desktop.
struct GlowRim: View {
    let colour: Color
    let power: Double
    let t: Double
    let thick: CGFloat

    private var notchW: CGFloat {
        guard let screen = NSScreen.main, screen.auxiliaryTopLeftArea != nil else { return 0 }
        return IslandPanel.notchWidth
    }
    private var notchD: CGFloat { NSScreen.main?.safeAreaInsets.top ?? 0 }

    var body: some View {
        let shape = ScreenOutline(notchWidth: notchW, notchDepth: notchD, corner: 12)
        let widths: [CGFloat] = [2, 6, 14, 28]
        let alphas: [Double] = [1.0, 0.5, 0.22, 0.10]
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                shape.stroke(colour.opacity(alphas[i] * power), lineWidth: widths[i] * thick)
            }
            shape.stroke(Color.white.opacity(0.5 * power), lineWidth: 1.1)
        }
        .blendMode(.plusLighter)
        .mask(
            AngularGradient(gradient: Gradient(colors: [.white, .white.opacity(0.4), .white, .white.opacity(0.3), .white]),
                            center: .center, angle: .degrees(t * 25))
        )
        .allowsHitTesting(false)
    }
}

/// Soft light in the four corners of the screen.
struct GlowCorners: View {
    let color: Color
    let depth: CGFloat
    let opacity: Double

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                RadialGradient(colors: [color.opacity(opacity), color.opacity(opacity * 0.3), color.opacity(0)],
                               center: UnitPoint(x: i % 2 == 0 ? 0 : 1, y: i < 2 ? 0 : 1),
                               startRadius: 0, endRadius: depth * 2.2)
            }
        }
        .allowsHitTesting(false)
    }
}
