import SwiftUI

/// The words of the current line become stars. They light up one by one as the line is sung, and a
/// thin line joins each new star to the last, drawing a constellation. `soft` makes the Aura version:
/// glowing orbs and a blurred thread instead of sharp sparkles.
struct ConstellationLyrics: View {
    let words: [String]
    let progress: Double          // 0...1 through the line
    let seed: Int                 // every line gets its own seed, so every line is a new shape
    let soft: Bool
    var scale: CGFloat = 1

    var body: some View {
        GeometryReader { g in
            let n = words.count
            let fs = CGFloat(max(11, min(46 * Double(scale), (52 - Double(n) * 2.2) * Double(scale))))
            let layout = place(g.size, fs)
            let x = min(Double(n), progress * Double(n) * 1.2 + 0.2)     // word k lights up when x reaches k
            ZStack {
                if n > 1 {
                    Path { p in
                        for (k, pt) in layout.points.enumerated() { if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) } }
                    }
                    .trim(from: 0, to: CGFloat(min(1, x / Double(n - 1))))
                    .stroke(Color.white.opacity(soft ? 0.35 : 0.8),
                            style: StrokeStyle(lineWidth: (soft ? 3 : 1.3) * scale, lineCap: .round, lineJoin: .round))
                    .blur(radius: soft ? 3 : 0)
                    .shadow(color: .white.opacity(0.5), radius: soft ? 0 : 3)
                }
                ForEach(0..<n, id: \.self) { k in
                    StarNode(word: words[k], on: Double(k) <= x, soft: soft, size: Double(fs), scale: scale, above: layout.above[k])
                        .position(layout.points[k])
                }
            }
        }
    }

    /// Scatters the words anywhere on the screen. Each word tries up to 80 random spots and takes the first
    /// one that is well clear of the words already placed, so labels never pile up on each other.
    private func place(_ size: CGSize, _ fs: CGFloat) -> (points: [CGPoint], above: [Bool]) {
        var rng = SeededRNG(s: UInt64(truncatingIfNeeded: abs(seed)) &* 2654435761 &+ 11)
        let m = 30 * scale
        var boxes: [CGRect] = [], pts: [CGPoint] = [], above: [Bool] = []
        for w in words {
            let lw = CGFloat(max(w.count, 1)) * fs * 0.58 + 20
            let lh = fs * 2.4 + 20
            let loX = min(lw / 2 + m, size.width / 2), hiX = max(size.width - lw / 2 - m, size.width / 2)
            let loY = min(lh / 2 + m, size.height / 2), hiY = max(size.height - lh / 2 - m, size.height / 2)
            var best = CGPoint(x: size.width / 2, y: size.height / 2)
            var bestScore: CGFloat = -1
            for _ in 0..<80 {
                let x = CGFloat.random(in: loX...hiX, using: &rng)
                let y = CGFloat.random(in: loY...hiY, using: &rng)
                let box = CGRect(x: x - lw / 2, y: y - lh / 2, width: lw, height: lh)
                var score = CGFloat.greatestFiniteMagnitude
                for o in boxes {
                    if box.insetBy(dx: -10, dy: -6).intersects(o) { score = 0; break }
                    score = min(score, hypot(box.midX - o.midX, box.midY - o.midY))
                }
                if score > bestScore { bestScore = score; best = CGPoint(x: x, y: y) }
                if score >= 160 * scale { break }
            }
            pts.append(best)
            boxes.append(CGRect(x: best.x - lw / 2, y: best.y - lh / 2, width: lw, height: lh))
            above.append(best.y > size.height * 0.68)
        }
        return (pts, above)
    }
}

struct StarNode: View {
    let word: String
    let on: Bool
    let soft: Bool
    let size: Double
    let scale: CGFloat
    let above: Bool
    @State private var pop = false

    var body: some View {
        ZStack {
            if soft {
                Circle()
                    .fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: 14 * scale))
                    .frame(width: 28 * scale, height: 28 * scale)
            } else {
                Image(systemName: "sparkle").font(.system(size: 16 * scale)).foregroundStyle(.white)
                    .shadow(color: .white, radius: 6)
            }
            Text(word)
                .font(.system(size: CGFloat(size), weight: soft ? .semibold : .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                .shadow(color: .white.opacity(soft ? 0.5 : 0.3), radius: soft ? 12 : 5)
                .fixedSize()
                .offset(y: (above ? CGFloat(-1) : CGFloat(1)) * (CGFloat(size) * 0.95 + 8 * scale))
        }
        .scaleEffect(pop ? 1 : 0.2).opacity(pop ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { pop = on } }
        .onChange(of: on) { _, v in withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { pop = v } }
    }
}

/// The album cover, blown up and blurred, drifting slowly behind the words, with a second
/// counter-rotating layer for depth and a dark vignette. Colours come straight from the cover.
struct AuraBackground: View {
    let url: URL?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                Color.black
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    .scaleEffect(1.6 + 0.1 * sin(t * 0.2)).rotationEffect(.degrees(t * 1.2))
                    .offset(x: 80 * sin(t * 0.11), y: 50 * cos(t * 0.13))
                    .blur(radius: 70).saturation(1.6).opacity(0.85)
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    .scaleEffect(1.2).rotationEffect(.degrees(-t * 2)).offset(x: -70 * cos(t * 0.09))
                    .blur(radius: 110).blendMode(.screen).opacity(0.45)
                Color.black.opacity(0.3)
                RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .center, startRadius: 200, endRadius: 900)
            }
            .ignoresSafeArea().clipped()
        }
    }
}
