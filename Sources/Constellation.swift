import SwiftUI

/// The words of the current line become stars. They light up one by one as the line is sung, and a
/// thin line joins each new star to the last, drawing a constellation. `soft` makes the Aura version:
/// glowing orbs and a blurred thread instead of sharp sparkles.
///
/// Two things matter here, because the lock screen gives Aura a narrow column beside the cover:
/// the words must wrap inside that column at a size that fits, and the thread must run through them
/// in a gentle wave — random positions per word drew a ragged zig-zag that spilled out of the column.
struct ConstellationLyrics: View {
    let words: [String]
    let progress: Double          // 0...1 through the line
    let seed: Int                 // every line gets its own seed, so every line is a new shape
    let soft: Bool
    var scale: CGFloat = 1
    var tint: Color = .white

    private struct Layout {
        var points: [CGPoint] = []
        var size: CGFloat = 12
    }

    var body: some View {
        GeometryReader { g in
            let l = layout(g.size)
            let x = litCount(n: words.count, progress: progress)
            ZStack {
                thread(l, n: words.count, x: x)
                ForEach(0..<words.count, id: \.self) { k in
                    StarNode(word: words[k], on: Double(k) <= x, soft: soft,
                             size: Double(l.size), scale: scale, above: false, tint: tint)
                        .position(l.points[min(k, l.points.count - 1)])
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
        }
    }

    private func litCount(n: Int, progress: Double) -> Double {
        min(Double(n), progress * Double(n) * 1.2 + 0.2)
    }

    private func margin(_ size: CGSize) -> CGFloat {
        max(4, min(20 * scale, size.width * 0.04, size.height * 0.04))
    }

    /// Real width of a word in the font the star uses. Guessing at "0.55 of the font size per letter" made
    /// neighbouring words overlap, because a bold rounded face is wider than that.
    private func width(_ word: String, _ fs: CGFloat) -> CGFloat {
        let base = NSFont.systemFont(ofSize: fs, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: fs) } ?? base
        return (word as NSString).size(withAttributes: [.font: font]).width * 1.08 + fs * 0.3
    }

    /// Wraps the words like text, shrinking until every row fits the column and no row touches the next.
    private static var cache: [String: Layout] = [:]

    private func layout(_ size: CGSize) -> Layout {
        let key = "\(seed)|\(Int(size.width))x\(Int(size.height))|\(scale)|" + words.joined(separator: " ")
        if let hit = Self.cache[key] { return hit }
        let made = computeLayout(size)
        if Self.cache.count > 24 { Self.cache.removeAll() }
        Self.cache[key] = made
        return made
    }

    private func computeLayout(_ size: CGSize) -> Layout {
        let n = words.count
        guard n > 0, size.width > 4, size.height > 4 else {
            // First pass of a GeometryReader can be zero-sized: still return one point per word.
            return Layout(points: Array(repeating: CGPoint(x: size.width / 2, y: size.height / 2), count: max(words.count, 1)))
        }
        let m = margin(size)
        let usableW = max(20, size.width - 2 * m)
        let rowStep: CGFloat = 1.9                                   // row spacing in font sizes: label, glow and thread never meet the next row
        // Font size from the word count, in small typed steps so the compiler never has to guess.
        let sc = Double(scale)
        let byCount: Double = (52.0 - Double(n) * 2.2) * sc
        let capped: Double = min(46.0 * sc, byCount)
        var fs = CGFloat(max(11.0, capped))

        var rows: [[Int]] = []
        for _ in 0..<60 {
            rows = wrap(fs: fs, usableW: usableW)
            // Summed row by row in a plain loop: the nested map/reduce here made the
            // compiler give up with "unable to type-check this expression in reasonable time".
            var widest: CGFloat = 0
            for row in rows {
                let text = row.map { width(words[$0], fs) }.reduce(0, +)
                let gaps = CGFloat(max(row.count - 1, 0)) * fs * 0.5
                widest = max(widest, text + gaps)
            }
            let height = CGFloat(rows.count) * fs * rowStep
            if widest <= usableW && height <= size.height - 2 * m { break }
            fs *= 0.93
            if fs < 8 { fs = 8; rows = wrap(fs: fs, usableW: usableW); break }
        }

        var pts: [CGPoint] = []
        let count = max(rows.count, 1)
        let blockH = CGFloat(count) * fs * rowStep
        let top = m + max(0, (size.height - 2 * m - blockH) / 2)
        for (r, row) in rows.enumerated() {
            let widths = row.map { width(words[$0], fs) }
            let gap = fs * 0.5
            let rowW = widths.reduce(0, +) + CGFloat(max(row.count - 1, 0)) * gap
            var x = m + max(0, (usableW - rowW) / 2)
            let rowY = top + CGFloat(r) * fs * rowStep + fs * rowStep / 2
            for (i, w) in widths.enumerated() {
                let angle: Double = Double(seed) * 0.7 + Double(r) * 2.1 + Double(i) * 1.3
                let drift: CGFloat = CGFloat(sin(angle)) * fs * 0.12
                pts.append(CGPoint(x: x + w / 2, y: rowY + drift))
                x += w + gap
            }
        }
        return Layout(points: pts, size: fs)
    }

    private func wrap(fs: CGFloat, usableW: CGFloat) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var used: CGFloat = 0
        for (i, w) in words.enumerated() {
            let wd = width(w, fs)
            let gap = used > 0 ? fs * 0.5 : 0
            if used > 0, used + gap + wd > usableW {
                rows.append([i]); used = wd
            } else {
                rows[rows.count - 1].append(i); used += gap + wd
            }
        }
        return rows
    }

    /// The thread is drawn as the line is sung, on Needle's own drawer curve.
    @ViewBuilder
    private func thread(_ l: Layout, n: Int, x: Double) -> some View {
        if n > 1, l.points.count > 1 {
            let trimEnd = CGFloat(min(1, x / Double(n - 1)))
            Path { p in
                for (k, pt) in l.points.enumerated() {
                    if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            .trim(from: 0, to: trimEnd)
            .stroke(tint.opacity(soft ? 0.30 : 0.8),
                    style: StrokeStyle(lineWidth: (soft ? 2.4 : 1.3) * scale, lineCap: .round, lineJoin: .round))
            .blur(radius: soft ? 3 : 0)
            .shadow(color: tint.opacity(0.5), radius: soft ? 0 : 3)
            .animation(.timingCurve(0.32, 0.72, 0, 1, duration: 0.45), value: x)
        }
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

    /// How far the label sits above or below its sparkle (Aura keeps the word on its star).
    private var labelLift: CGFloat {
        if soft { return 0 }
        let dir: CGFloat = above ? -1 : 1
        let gap: CGFloat = CGFloat(size) * 0.95 + 8 * scale
        return dir * gap
    }

    var body: some View {
        ZStack {
            if soft {
                Circle()
                    .fill(RadialGradient(colors: [tint, tint.opacity(0)], center: .center, startRadius: 0, endRadius: 12 * scale))
                    .frame(width: 26 * scale, height: 26 * scale)
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
                .fixedSize()
                // Aura keeps the word on its star; only the sharp version lifts the label off the sparkle.
                .offset(y: labelLift)
        }
        .scaleEffect(pop ? 1 : 0.2).opacity(pop ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { pop = on } }
        .onChange(of: on) { _, v in withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { pop = v } }
    }
}
