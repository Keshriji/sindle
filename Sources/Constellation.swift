import SwiftUI

/// The words of the current line become stars. They light up one by one as the line is sung, and a
/// thin line joins each new star to the last, drawing a constellation. `soft` makes the Aura version:
/// glowing orbs and a blurred thread instead of sharp sparkles.
///
/// The words have to fit whatever box they are given. On the lock screen that box is the narrow
/// column beside the cover, and a fixed font size used to push every long word onto the same centre
/// point, where they piled up on top of each other and spilled over the song card. The size is now
/// fitted to the box and every word gets its own row, so the line is readable at any width.
struct ConstellationLyrics: View {
    let words: [String]
    let progress: Double          // 0...1 through the line
    let seed: Int                 // every line gets its own seed, so every line is a new shape
    let soft: Bool
    var scale: CGFloat = 1
    var tint: Color = .white

    var body: some View {
        GeometryReader { g in
            let fs = fitted(g.size)
            let layout = place(g.size, fs)
            let x = litCount(n: words.count, progress: progress)
            ZStack {
                threadView(n: words.count, layout: layout, x: x)
                starsView(n: words.count, layout: layout, x: x, fs: fs)
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
        }
    }

    private func fontSize(n: Int) -> CGFloat {
        CGFloat(max(11, min(46 * Double(scale), (52 - Double(n) * 2.2) * Double(scale))))
    }

    /// Shrinks the type until the longest word fits across and every word has a row of its own.
    private func fitted(_ size: CGSize) -> CGFloat {
        let n = max(words.count, 1)
        let longest = CGFloat(words.map { $0.count }.max() ?? 1)
        var fs = fontSize(n: n)
        if size.width > 0 {
            fs = min(fs, size.width * 0.86 / max(longest * 0.58, 0.58))      // one label across
            let row = (size.height - 2 * margin(size)) / CGFloat(n)
            fs = min(fs, (row - 16) / 2.4)                                    // one row per word
        }
        return max(8, fs)
    }

    private func margin(_ size: CGSize) -> CGFloat {
        max(4, min(24 * scale, size.width * 0.05, size.height * 0.04))
    }

    private func litCount(n: Int, progress: Double) -> Double {
        min(Double(n), progress * Double(n) * 1.2 + 0.2)
    }

    @ViewBuilder
    private func threadView(n: Int, layout: (points: [CGPoint], above: [Bool]), x: Double) -> some View {
        if n > 1 {
            let trimEnd = CGFloat(min(1, x / Double(n - 1)))
            Path { p in
                for (k, pt) in layout.points.enumerated() {
                    if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            .trim(from: 0, to: trimEnd)
            .stroke(tint.opacity(soft ? 0.35 : 0.8),
                    style: StrokeStyle(lineWidth: (soft ? 3 : 1.3) * scale, lineCap: .round, lineJoin: .round))
            .blur(radius: soft ? 3 : 0)
            .shadow(color: tint.opacity(0.5), radius: soft ? 0 : 3)
            // the thread is drawn as the line is sung, on Needle's own drawer curve
            .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.45), value: x)
        }
    }

    @ViewBuilder
    private func starsView(n: Int, layout: (points: [CGPoint], above: [Bool]), x: Double, fs: CGFloat) -> some View {
        ForEach(0..<n, id: \.self) { k in
            StarNode(word: words[k], on: Double(k) <= x, soft: soft, size: Double(fs), scale: scale, above: layout.above[k], tint: tint)
                .position(layout.points[k])
        }
    }

    /// One row per word, scattered sideways. Rows cannot collide, so a line of long words stays a
    /// line instead of a heap, and every point is kept inside the box.
    private func place(_ size: CGSize, _ fs: CGFloat) -> (points: [CGPoint], above: [Bool]) {
        var rng = SeededRNG(s: UInt64(truncatingIfNeeded: abs(seed)) &* 2654435761 &+ 11)
        let n = words.count
        let m = margin(size)
        let rowH = min(fs * 2.4 + 16, (size.height - 2 * m) / CGFloat(max(n, 1)))
        var pts: [CGPoint] = [], above: [Bool] = []
        for (i, w) in words.enumerated() {
            let lw = min(CGFloat(max(w.count, 1)) * fs * 0.58 + 12, max(size.width - 2 * m, 1))
            let loX = min(lw / 2 + m, size.width - m)
            let hiX = max(size.width - lw / 2 - m, m)
            let loY = min(rowH / 2 + m, size.height - m)
            let hiY = max(size.height - rowH / 2 - m, m)
            let y = n == 1 ? size.height / 2
                           : loY + (hiY - loY) * CGFloat(i) / CGFloat(n - 1)
            let x = hiX > loX ? CGFloat.random(in: loX...hiX, using: &rng) : size.width / 2
            pts.append(CGPoint(x: x, y: y))
            above.append(false)
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
    var tint: Color = .white
    @State private var pop = false

    var body: some View {
        ZStack {
            if soft {
                Circle()
                    .fill(RadialGradient(colors: [tint, tint.opacity(0)], center: .center, startRadius: 0, endRadius: 14 * scale))
                    .frame(width: 28 * scale, height: 28 * scale)
            } else {
                Image(systemName: "sparkle").font(.system(size: 16 * scale)).foregroundStyle(tint)
                    .shadow(color: tint, radius: 6)
            }
            Text(word)
                .font(.system(size: CGFloat(size), weight: soft ? .semibold : .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                .shadow(color: tint.opacity(soft ? 0.5 : 0.3), radius: soft ? 12 : 5)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .fixedSize()
                // Aura keeps the word on its star; only the sharp version lifts the label off the sparkle.
                .offset(y: soft ? 0 : (above ? -1 : 1) * (CGFloat(size) * 0.95 + 8 * scale))
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
