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

    /// Wraps the words like text, shrinking until they fit the column in at most four rows.
    private func layout(_ size: CGSize) -> Layout {
        let n = words.count
        guard n > 0, size.width > 4, size.height > 4 else {
            // First pass of a GeometryReader can be zero-sized: still return one point per word so
            // the stars can be indexed safely.
            return Layout(points: Array(repeating: CGPoint(x: size.width / 2, y: size.height / 2), count: max(words.count, 1)))
        }
        let m = margin(size)
        let usableW = max(20, size.width - 2 * m)
        let longest = CGFloat(words.map { $0.count }.max() ?? 1)

        var fs = CGFloat(max(11, min(46 * Double(scale), (52 - Double(n) * 2.2) * Double(scale))))
        fs = min(fs, usableW / max(longest * 0.55, 0.55))          // one word never wider than the column
        let maxRows = min(4, max(1, n))

        var rows: [[Int]] = []
        for _ in 0..<40 {                                            // shrink until it wraps and fits
            rows = wrap(fs: fs, usableW: usableW)
            let height = CGFloat(rows.count) * fs * 1.55
            if rows.count <= maxRows && height <= size.height - 2 * m { break }
            fs *= 0.92
            if fs < 8 { fs = 8; rows = wrap(fs: fs, usableW: usableW); break }
        }

        // Rows stack through the column; the thread drifts a little inside each row.
        var pts: [CGPoint] = []
        let count = max(rows.count, 1)
        let blockH = CGFloat(count) * fs * 1.55
        let top = m + max(0, (size.height - 2 * m - blockH) / 2)
        for (r, row) in rows.enumerated() {
            let widths = row.map { CGFloat(words[$0].count) * fs * 0.55 }
            let rowW = widths.reduce(0, +) + CGFloat(max(row.count - 1, 0)) * fs * 0.42
            var x = m + max(0, (usableW - rowW) / 2)
            let rowY = top + CGFloat(r) * fs * 1.55 + fs * 0.78
            for (i, w) in widths.enumerated() {
                let drift = sin(Double(seed) * 0.7 + Double(r) * 2.1 + Double(i) * 1.3) * Double(fs) * 0.16
                pts.append(CGPoint(x: x + w / 2, y: rowY + CGFloat(drift)))
                x += w + fs * 0.42
            }
        }
        return Layout(points: pts, size: fs)
    }

    private func wrap(fs: CGFloat, usableW: CGFloat) -> [[Int]] {
        var rows: [[Int]] = [[]]
        var used: CGFloat = 0
        for (i, w) in words.enumerated() {
            let width = CGFloat(w.count) * fs * 0.55
            let gap = used > 0 ? fs * 0.42 : 0
            if used > 0, used + gap + width > usableW {
                rows.append([i]); used = width
            } else {
                rows[rows.count - 1].append(i); used += gap + width
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
