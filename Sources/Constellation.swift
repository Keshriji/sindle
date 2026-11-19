import SwiftUI

/// The words of the current line become a constellation: every word is a four-point star, a thin
/// line joins the stars in the order they are sung, and a second set of chords crosses the shape so
/// it reads as a star map instead of a scribble. Each word pops in — star first, then its label
/// fades up out of a blur — as the line reaches it.
///
/// The points are scattered in two dimensions, measured with the real rounded font so labels do not
/// overlap, and every point is kept inside the box it is given.
struct ConstellationLyrics: View {
    let words: [String]
    let progress: Double          // 0...1 through the line
    let seed: Int                 // every line gets its own seed, so every line is a new shape
    let soft: Bool                // Aura adds a glow halo and a blurred thread
    var scale: CGFloat = 1
    var tint: Color = .white

    var body: some View {
        GeometryReader { g in
            let fs = fitted(g.size)
            let layout = place(g.size, fs)
            let x = litCount(n: words.count, progress: progress)
            ZStack {
                links(layout, x: x)
                stars(layout, x: x, fs: fs)
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
        }
    }

    private func litCount(n: Int, progress: Double) -> Double {
        min(Double(n), progress * Double(n) * 1.2 + 0.2)
    }

    private func margin(_ size: CGSize) -> CGFloat {
        max(4, min(24 * scale, size.width * 0.05, size.height * 0.04))
    }

    /// Real width of a word in the font the star uses. Guessing at "0.55 of the font size per letter"
    /// made neighbouring words overlap, because a semibold rounded face is wider than that.
    private func width(_ word: String, _ fs: CGFloat) -> CGFloat {
        let base = NSFont.systemFont(ofSize: fs, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: fs) } ?? base
        return (word as NSString).size(withAttributes: [.font: font]).width * 1.08 + fs * 0.3
    }

    /// Shrinks the type until the longest word fits across and the words have room to spread out.
    func fitted(_ size: CGSize) -> CGFloat {
        let n = max(words.count, 1)
        var fs = CGFloat(max(11, min(46 * Double(scale), (52 - Double(n) * 2.2) * Double(scale))))
        guard size.width > 0, size.height > 0 else { return fs }
        // A 100 pt sample: the label width grows in proportion to the font size.
        let unit = (words.map { width($0, 100) }.max() ?? 100) / 100
        fs = min(fs, size.width * 0.84 / max(unit, 0.1))                   // one label across
        let rows = CGFloat(max(2, Int(Double(n).squareRoot().rounded(.up))))
        fs = min(fs, (size.height - 2 * margin(size)) / (rows * 2.45))     // enough rows to spread
        return max(8, fs)
    }

    // MARK: lines

    /// The chain through the words in sung order, plus chords skipping one word so the shape crosses
    /// itself like a real constellation. The part already sung is bright; the rest stays faint so the
    /// whole shape is visible from the first word.
    @ViewBuilder
    private func links(_ layout: (points: [CGPoint], above: [Bool]), x: Double) -> some View {
        let pts = layout.points
        let n = pts.count
        if n > 1 {
            let chain = Path { p in
                p.move(to: pts[0])
                for i in 1..<n { p.addLine(to: pts[i]) }
            }
            let chords = Path { p in
                guard n > 2 else { return }
                for i in 0..<(n - 2) { p.move(to: pts[i]); p.addLine(to: pts[i + 2]) }
            }
            let shot = CGFloat(min(1, max(0, x / Double(n - 1))))
            let line = (soft ? 2.2 : 1.1) * scale
            ZStack {
                chords.stroke(tint.opacity(soft ? 0.16 : 0.14),
                              style: StrokeStyle(lineWidth: line * 0.9, lineCap: .round, lineJoin: .round))
                chain.stroke(tint.opacity(soft ? 0.22 : 0.20),
                             style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
                // the thread is drawn as the line is sung, on Needle's own drawer curve
                chain.trim(from: 0, to: shot)
                    .stroke(tint.opacity(soft ? 0.75 : 0.95),
                            style: StrokeStyle(lineWidth: line * 1.35, lineCap: .round, lineJoin: .round))
                    .blur(radius: soft ? 2.4 : 0)
                    .shadow(color: tint.opacity(0.6), radius: soft ? 4 : 2)
                    .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.45), value: x)
            }
        }
    }

    // MARK: stars

    @ViewBuilder
    private func stars(_ layout: (points: [CGPoint], above: [Bool]), x: Double, fs: CGFloat) -> some View {
        let n = words.count
        let current = max(0, min(n - 1, Int(x.rounded(.down))))
        ForEach(0..<n, id: \.self) { k in
            StarNode(word: words[k],
                     on: Double(k) <= x,
                     active: k == current && Double(k) <= x,
                     soft: soft,
                     size: Double(fs),
                     scale: scale,
                     above: layout.above[k],
                     tint: tint)
                .position(layout.points[k])
        }
    }

    /// Scatters the stars across the box in two dimensions, keeping a minimum gap between labels.
    /// Each new point is chosen from a handful of candidates as the one furthest from the stars
    /// already placed, which gives an even, star-map spread rather than clumps.
    func place(_ size: CGSize, _ fs: CGFloat) -> (points: [CGPoint], above: [Bool]) {
        let n = words.count
        guard n > 0, size.width > 0, size.height > 0 else { return ([], []) }
        if n == 1 { return ([CGPoint(x: size.width / 2, y: size.height / 2)], [false]) }

        var rng = SeededRNG(s: UInt64(truncatingIfNeeded: abs(seed)) &* 2654435761 &+ 11)
        let m = margin(size)
        let labelH = CGFloat(fs) * 1.2 + 12 * scale
        let widths: [CGFloat] = words.map { min(width($0, fs), max(size.width - 2 * m, 1)) }

        var pts: [CGPoint] = [], above: [Bool] = []
        for i in 0..<n {
            let lw = widths[i]
            let loX = min(lw / 2 + m, size.width - m)
            let hiX = max(size.width - lw / 2 - m, m)
            let loY = min(m + labelH * 0.5, size.height - m)
            let hiY = max(size.height - m - labelH * 1.15, loY)

            var best = CGPoint(x: size.width / 2, y: size.height / 2)
            var bestScore = -Double.greatestFiniteMagnitude
            for _ in 0..<(pts.isEmpty ? 1 : 40) {
                let c = CGPoint(x: hiX > loX ? CGFloat.random(in: loX...hiX, using: &rng) : (loX + hiX) / 2,
                                y: hiY > loY ? CGFloat.random(in: loY...hiY, using: &rng) : (loY + hiY) / 2)
                var score = Double.greatestFiniteMagnitude
                for (j, p) in pts.enumerated() {
                    let dx = Double(c.x - p.x) / Double((lw + widths[j]) / 2 + 16 * scale)
                    let dy = Double(c.y - p.y) / Double(labelH * 1.1 + 14 * scale)
                    score = min(score, (dx * dx + dy * dy).squareRoot())
                }
                if score > bestScore { bestScore = score; best = c }
            }
            pts.append(best)
            // labels hang under their star, and flip above it when there is no room below
            above.append(best.y + labelH * 0.95 > size.height - m)
        }
        return (pts, above)
    }
}

/// One word on its star. The star pops in first, then the label rises out of a blur — the "text pop
/// up" that makes each new word feel like it lands on the map.
struct StarNode: View {
    let word: String
    let on: Bool
    let active: Bool
    let soft: Bool
    let size: Double
    let scale: CGFloat
    let above: Bool
    var tint: Color = .white
    @State private var pop = false

    private var side: CGFloat { CGFloat(size) * (active ? 1.05 : 0.8) }

    var body: some View {
        ZStack {
            if soft {
                Circle()
                    .fill(RadialGradient(colors: [tint.opacity(0.75), tint.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: side * 1.9))
                    .frame(width: side * 3.8, height: side * 3.8)
                    .opacity(0.9)
            }
            if active {
                Circle()
                    .stroke(tint.opacity(0.55), lineWidth: 1)
                    .frame(width: side * 2.1, height: side * 2.1)
                    .blur(radius: 0.6)
                    .scaleEffect(pop ? 1 : 0.5)
            }
            FourPointStar()
                .fill(tint)
                .frame(width: side, height: side)
                .shadow(color: tint.opacity(0.85), radius: active ? 9 : 4)
                .scaleEffect(pop ? 1 : 0.55)
                .animation(.spring(response: 0.42, dampingFraction: 0.52), value: pop)

            Text(word)
                .font(.system(size: CGFloat(size), weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.65), radius: 3, y: 1)
                .shadow(color: tint.opacity(soft ? 0.55 : 0.3), radius: soft ? 10 : 4)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .fixedSize()
                .offset(y: (above ? -1 : 1) * (CGFloat(size) * 0.92 + 10 * scale))
                .scaleEffect(pop ? 1 : 0.7, anchor: above ? .bottom : .top)
                .blur(radius: pop ? 0 : 1.5)
                // words not sung yet still show, so the whole star map reads like the print
                .opacity(pop ? 1 : 0.45)
                .animation(.spring(response: 0.5, dampingFraction: 0.62).delay(0.06), value: pop)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.2)) { pop = on } }
        .onChange(of: on) { _, v in withAnimation(.easeOut(duration: 0.2)) { pop = v } }
        .animation(.easeOut(duration: 0.28), value: active)
    }
}

/// A thin four-point star: the star-shaped dot every word sits on.
struct FourPointStar: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let waist = r * 0.16
        for i in 0..<8 {
            let a = Double(i) * .pi / 4 - .pi / 2
            let rr = i.isMultiple(of: 2) ? r : waist
            let pt = CGPoint(x: c.x + CGFloat(cos(a)) * rr, y: c.y + CGFloat(sin(a)) * rr)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

/// The album cover, full screen, stretched and heavily blurred, breathing and drifting very slowly.
/// This is Beat Glow's room: the cover fills the whole screen instead of a card, and it never sits
/// still, so the lock screen moves with the song instead of showing a still.
struct StretchBackdrop: View {
    let url: URL?

    var body: some View {
        GeometryReader { g in
            // 12 fps: the layers are blurred beyond recognition, so a faster clock only costs CPU.
            TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                ZStack {
                    cover(g.size)
                        // a slow stretch: the cover pulls wide and tall at different rates
                        .scaleEffect(x: 1.18 + 0.05 * sin(t * 0.07), y: 1.30 + 0.05 * cos(t * 0.05))
                        .offset(x: 20 * sin(t * 0.045), y: 16 * cos(t * 0.038))
                        .blur(radius: 46)
                        .saturation(1.35)
                    cover(g.size)
                        .scaleEffect(x: 1.06, y: 1.14)
                        .offset(x: -14 * cos(t * 0.031), y: 10 * sin(t * 0.041))
                        .blur(radius: 92)
                        .blendMode(.screen)
                        .opacity(0.5)
                }
                .frame(width: g.size.width, height: g.size.height)
                .clipped()
            }
        }
    }

    private func cover(_ s: CGSize) -> some View {
        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.black }
            .frame(width: s.width, height: s.height)
            .clipped()
    }
}

/// A light that slides around the screen edge on the song's beat: two soft white blooms travel the
/// frame, brightening with every kick the audio listener hears. With no sound to listen to it falls
/// back to a slow drift so the style is never dead.
struct BeatGlowEdge: View {
    @ObservedObject var audio: AudioLevel
    var playing: Bool
    var tint: Color = .white
    var intensity: Double = 1
    var corner: CGFloat = 26
    var inset: CGFloat = 2

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let live = tl.date.timeIntervalSince(audio.lastSample) < 1.5
            let fallback = 0.3 + 0.3 * (0.5 + 0.5 * sin(t * 2.4))
            let beat = playing ? (live ? audio.level : fallback) : 0.06
            let spin = Angle.degrees((playing ? t * 44 : t * 10).truncatingRemainder(dividingBy: 360))
            ZStack {
                // the wide bloom that lights the bezel
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(bloom(spin), lineWidth: 5 + 11 * beat)
                    .blur(radius: 20 + 14 * beat)
                    .opacity((0.30 + 0.55 * beat) * intensity)
                // the travelling highlight itself
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(bloom(spin), lineWidth: 1.6 + 1.8 * beat)
                    .blur(radius: 2)
                    .opacity((0.45 + 0.5 * beat) * intensity)
                // a hairline frame so the glass edge always reads, even between beats
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(tint.opacity(0.10), lineWidth: 1)
            }
            .padding(inset)
        }
        .allowsHitTesting(false)
    }

    private func bloom(_ spin: Angle) -> AngularGradient {
        AngularGradient(stops: [
            .init(color: .clear, location: 0.00),
            .init(color: tint.opacity(0.20), location: 0.12),
            .init(color: .white, location: 0.24),
            .init(color: tint.opacity(0.35), location: 0.36),
            .init(color: .clear, location: 0.52),
            .init(color: tint.opacity(0.18), location: 0.62),
            .init(color: .white, location: 0.76),
            .init(color: .clear, location: 0.90),
            .init(color: .clear, location: 1.00)
        ], center: .center, angle: spin)
    }
}
