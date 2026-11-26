import SwiftUI
import AppKit

// MARK: - Big Words

/// The cover colour pushed to a strong, bright tone so a huge word reads clearly on top of the same cover.
/// A grey cover has no colour to push, so it stays white.
func vividColour(_ c: Color) -> Color {
    let ns: NSColor = NSColor(c).usingColorSpace(.sRGB) ?? NSColor.white
    var h: CGFloat = 0
    var s: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    ns.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    if s < 0.12 { return Color.white }
    return Color(hue: Double(h), saturation: Double(max(s, 0.55)), brightness: 0.98)
}

/// A small picture that rides next to a word when the word is something you can draw ("lights", "down", "heart"...).
enum BigWordIcon {
    private static let table: [String: String] = [
        "morning": "sunrise.fill", "sunrise": "sunrise.fill", "sun": "sun.max.fill", "sunshine": "sun.max.fill",
        "light": "lightbulb.fill", "lights": "lightbulb.fill", "night": "moon.fill", "moon": "moon.fill",
        "dream": "moon.stars.fill", "dreams": "moon.stars.fill", "star": "star.fill", "stars": "star.fill",
        "low": "arrow.down", "down": "arrow.down", "fall": "arrow.down", "falling": "arrow.down",
        "up": "arrow.up", "high": "arrow.up", "rise": "arrow.up", "rising": "arrow.up",
        "heart": "heart.fill", "love": "heart.fill", "kiss": "heart.fill", "fire": "flame.fill", "burn": "flame.fill",
        "rain": "cloud.rain.fill", "cloud": "cloud.fill", "clouds": "cloud.fill", "sky": "cloud.fill",
        "cry": "drop.fill", "tears": "drop.fill", "ocean": "water.waves", "sea": "water.waves", "water": "drop.fill",
        "music": "music.note", "song": "music.note", "sing": "music.note", "dance": "figure.dance",
        "time": "clock.fill", "world": "globe", "eyes": "eye.fill", "home": "house.fill", "fly": "airplane",
        "run": "figure.run", "cold": "snowflake", "snow": "snowflake", "money": "dollarsign.circle.fill",
        "phone": "phone.fill", "car": "car.fill", "gone": "arrow.right", "away": "arrow.right"
    ]

    static func symbol(for word: String) -> String? {
        let key: String = word.lowercased().filter { $0.isLetter }
        return table[key]
    }
}

/// The cover, full bleed and barely softened, with a gentle darkening at the top and bottom so the words stand out.
struct BigWordsBackdrop: View {
    let url: URL?

    var body: some View {
        GeometryReader { g in
            ZStack {
                Color.black
                AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
                    .frame(width: g.size.width, height: g.size.height)
                    .clipped()
                    .blur(radius: 2)
                Color.black.opacity(0.16)
                LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.4)], startPoint: .top, endPoint: .bottom)
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
        }
    }
}

/// One word on the stack. `cursor` is which word is in front; the view is Animatable, so while the stack rolls
/// up to the next word every frame is drawn from the in-between value: the word swells from a small italic into
/// the huge one, the old one shrinks upward and fades, and the movement is smeared vertically.
struct BigWordView: View, Animatable {
    var cursor: Double
    let index: Double
    let text: String
    let colour: Color
    let size: CGSize

    var animatableData: Double {
        get { cursor }
        set { cursor = newValue }
    }

    var body: some View {
        let d: Double = index - cursor
        let a: Double = abs(d)
        let t: Double = min(a, 1.0)
        let chars: CGFloat = CGFloat(max(text.count, 2))
        let big: CGFloat = min(size.height * 0.22, size.width * 0.7 / (chars * 0.58))
        let fs: CGFloat = big * CGFloat(1.0 - 0.72 * t)
        let y: CGFloat = CGFloat(d) * size.height * 0.26
        let front: Bool = a < 0.5
        let isNext: Bool = d >= 0.5
        let motion: Double = abs(d - d.rounded())
        var fade: Double = 1.0
        if a > 1.0 {
            fade = max(0.0, 1.0 - (a - 1.0) * 1.5)
        } else if d < 0 {
            fade = 1.0 - 0.5 * t
        } else {
            fade = 1.0 - 0.05 * t
        }
        let tone: Color = front ? colour : (isNext ? Color.white : colour.opacity(0.75))
        let font: Font = isNext ? Font.system(size: fs, weight: .bold).italic()
                                : Font.system(size: fs, weight: front ? .heavy : .bold)
        let icon: String? = BigWordIcon.symbol(for: text)

        return HStack(spacing: fs * 0.18) {
            Text(text).font(font).tracking(-fs * 0.03)
            if let icon {
                Image(systemName: icon).font(.system(size: fs * 0.55, weight: .bold))
            }
        }
        .foregroundStyle(tone)
        .shadow(color: .black.opacity(front ? 0.4 : 0.55), radius: fs * 0.12, y: fs * 0.05)
        .fixedSize()
        .scaleEffect(x: 1, y: 1 + CGFloat(motion))
        .blur(radius: CGFloat(motion * 18))
        .opacity(fade)
        .offset(y: y)
    }
}

struct BigWordStage: View {
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
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    ForEach(window(cur)) { c in
                        BigWordView(cursor: cursor, index: Double(c.id), text: c.text, colour: colourFor(c.id), size: size)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .onChange(of: cur) { _, n in
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { cursor = Double(n) }
            }
        }
        .onAppear {
            chunks = AuraTimeline.build(lyrics.lines, pairing: false)
            cursor = Double(AuraTimeline.current(chunks, at: lockLivePos(track)))
        }
        .onChange(of: lyrics.lines) { _, new in chunks = AuraTimeline.build(new, pairing: false) }
    }

    /// Only the words near the front can be seen, so only those are drawn.
    private func window(_ cur: Int) -> [AuraChunk] {
        guard !chunks.isEmpty else { return [] }
        let lo = max(0, cur - 2)
        let hi = min(chunks.count - 1, max(cur, 0) + 3)
        guard lo <= hi else { return [] }
        return Array(chunks[lo...hi])
    }
}
