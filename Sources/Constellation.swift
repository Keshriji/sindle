import SwiftUI

/// The words of the current line become stars. They light up one by one as the line is sung, and a
/// thin line joins each new star to the last, drawing a constellation. `soft` makes the Aura version:
/// glowing orbs and a blurred thread instead of sharp sparkles.
struct ConstellationLyrics: View {
    let words: [String]
    let progress: Double          // 0...1 through the line
    let seed: Int                 // same line, same shape
    let soft: Bool
    var scale: CGFloat = 1

    var body: some View {
        GeometryReader { g in
            let n = words.count
            let pts = points(n, g.size)
            let x = progress * Double(n)                      // word k lights up when x reaches k
            let avg = Double(words.map { $0.count }.reduce(0, +)) / Double(max(n, 1))
            let spacing = Double(g.size.width) * 0.84 / Double(max(n - 1, 1))
            let fs = max(11, min(34 * Double(scale), spacing * 1.9 / max(avg * 0.6, 1)))
            ZStack {
                if n > 1 {
                    Path { p in
                        for (k, pt) in pts.enumerated() { if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) } }
                    }
                    .trim(from: 0, to: CGFloat(min(1, x / Double(n - 1))))
                    .stroke(Color.white.opacity(soft ? 0.3 : 0.75),
                            style: StrokeStyle(lineWidth: (soft ? 3 : 1.2) * scale, lineCap: .round, lineJoin: .round))
                    .blur(radius: soft ? 3 : 0)
                    .shadow(color: .white.opacity(0.5), radius: soft ? 0 : 3)
                }
                ForEach(0..<n, id: \.self) { k in
                    StarNode(word: words[k], on: Double(k) <= x, soft: soft, size: fs, scale: scale, above: k % 2 == 0)
                        .position(pts[k])
                }
            }
        }
    }

    private func points(_ n: Int, _ size: CGSize) -> [CGPoint] {
        var rng = SeededRNG(s: UInt64(truncatingIfNeeded: abs(seed)) &* 2654435761 &+ 11)
        let left = size.width * 0.08, right = size.width * 0.92
        return (0..<n).map { k in
            let fx = n == 1 ? CGFloat(0.5) : CGFloat(k) / CGFloat(n - 1)
            let jitter = CGFloat.random(in: -0.12...0.12, using: &rng)
            let y = size.height * (0.5 + (k % 2 == 0 ? -0.2 : 0.2) + jitter)
            return CGPoint(x: left + (right - left) * fx, y: y)
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
                .shadow(color: .white.opacity(soft ? 0.6 : 0.35), radius: soft ? 14 : 6)
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
                RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .center, startRadius: 200, endRadius: 900)
            }
            .ignoresSafeArea().clipped()
        }
    }
}
