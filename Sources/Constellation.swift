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
        var fs = CGFloat(max(11, min(46 * Double(scale), (52 - Double(n) * 2.2) * Double(scale))))

        var rows: [[Int]] = []
        for _ in 0..<60 {
            rows = wrap(fs: fs, usableW: usableW)
            let widest = rows.map { $0.map { width(words[$0], fs) }.reduce(0, +) + CGFloat(max($0.count - 1, 0)) * fs * 0.5 }.max() ?? 0
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
                let drift = sin(Double(seed) * 0.7 + Double(r) * 2.1 + Double(i) * 1.3) * Double(fs) * 0.12
                pts.append(CGPoint(x: x + w / 2, y: rowY + CGFloat(drift)))
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

/// Drifting panes of frosted glass over the blurred album cover. Each pane is a blurred, brightened copy of the
/// cover clipped to a rounded slab with a soft white rim, so light seems to bend through it. Slow, calm, and cheap
/// enough to run on the lock screen (15 frames a second).
struct GlassBackdrop: View {
    let url: URL?
    @State private var far: NSImage?        // tiny copy of the cover: scaled up it is already a smooth blur
    @State private var near: NSImage?       // a little sharper copy for the glass panes
    private struct Slab { let x: Double, y: Double, w: Double, h: Double, speed: Double, phase: Double, tilt: Double }
    private let slabs: [Slab] = [
        Slab(x: 0.22, y: 0.30, w: 0.46, h: 0.36, speed: 0.050, phase: 0.0, tilt: -9),
        Slab(x: 0.74, y: 0.26, w: 0.36, h: 0.46, speed: 0.040, phase: 1.7, tilt: 7),
        Slab(x: 0.50, y: 0.72, w: 0.56, h: 0.30, speed: 0.060, phase: 3.1, tilt: -4),
        Slab(x: 0.88, y: 0.78, w: 0.30, h: 0.34, speed: 0.045, phase: 4.6, tilt: 11)
    ]

    var body: some View {
        GeometryReader { g in
            TimelineView(.periodic(from: .now, by: 1.0 / 15.0)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                ZStack {
                    Color.black
                    cover(far, g.size).saturation(1.5).opacity(0.9)
                    ForEach(0..<slabs.count, id: \.self) { i in
                        let s = slabs[i]
                        let w = g.size.width * s.w, h = g.size.height * s.h
                        let dx = sin(t * s.speed + s.phase) * g.size.width * 0.05
                        let dy = cos(t * s.speed * 0.8 + s.phase) * g.size.height * 0.05
                        let shape = RoundedRectangle(cornerRadius: min(w, h) * 0.2, style: .continuous)
                        ZStack {
                            cover(near, g.size).offset(x: -dx * 3, y: -dy * 3)        // the cover slides behind the pane: the "bend"
                            Color.white.opacity(0.10)
                        }
                        .frame(width: w, height: h)
                        .clipShape(shape)
                        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05), .white.opacity(0.25)],
                                                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2))
                        .rotationEffect(.degrees(s.tilt + sin(t * s.speed * 1.3 + s.phase) * 3))
                        .position(x: g.size.width * s.x + dx, y: g.size.height * s.y + dy)
                    }
                    Color.black.opacity(0.30)                                          // keeps white lyrics readable on bright covers
                    RadialGradient(colors: [.clear, .black.opacity(0.5)], center: .center,
                                   startRadius: g.size.width * 0.25, endRadius: g.size.width * 0.8)
                }
                .frame(width: g.size.width, height: g.size.height)
                .clipped()
            }
        }
        .task(id: url) { await load() }
    }

    @ViewBuilder private func cover(_ img: NSImage?, _ size: CGSize) -> some View {
        if let img {
            Image(nsImage: img).resizable().interpolation(.high).scaledToFill()
                .frame(width: size.width * 1.2, height: size.height * 1.2)
        } else {
            Color.clear
        }
    }

    private func load() async {
        guard let url, let (data, _) = try? await URLSession.shared.data(from: url), let img = NSImage(data: data) else { return }
        let f = Self.shrink(img, to: 20), n = Self.shrink(img, to: 72)
        await MainActor.run { far = f; near = n }
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
