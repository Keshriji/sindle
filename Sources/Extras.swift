import SwiftUI
import AppKit

// MARK: Typing speed ("Keycap")
/// Counts keystrokes system-wide. Needs Accessibility permission (System Settings > Privacy & Security).
/// Only counts keys; it never records which keys.
final class TypingStore: ObservableObject {
    @Published var wpm = 0
    @Published var best = 0
    @Published var sounds = false
    @Published var trusted = false
    private var stamps: [Date] = []
    private var monitor: Any?
    private var timer: Timer?

    func start() {
        trusted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, !e.isARepeat else { return }
            self.stamps.append(Date())
            if self.sounds { NSSound(named: "Tink")?.play() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.update() }
    }

    private func update() {
        stamps.removeAll { $0 < Date().addingTimeInterval(-10) }
        let w = Int(Double(stamps.count) / 5.0 * 6.0)       // 5 keys = 1 word, scaled from 10 s to 60 s
        if w != wpm { wpm = w }
        best = max(best, w)
        if !trusted { trusted = AXIsProcessTrusted() }
    }
}

struct TypingPage: View {
    @ObservedObject var typing: TypingStore
    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [.white, Color(white: 0.78)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: .black.opacity(0.5), radius: 0, y: 5)
                Text("\(typing.wpm)").font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.black).contentTransition(.numericText())
            }
            .frame(width: 74, height: 64)
            .offset(y: typing.wpm > 0 ? 3 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: typing.wpm)
            VStack(alignment: .leading, spacing: 6) {
                Text("words per minute").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Text("Best this session: \(typing.best)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                Button { typing.sounds.toggle() } label: {
                    Label(typing.sounds ? "Key sounds on" : "Key sounds off",
                          systemImage: typing.sounds ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 11)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(.white.opacity(0.14)))
                }.buttonStyle(.plain)
                if !typing.trusted {
                    Text("Allow Spindle under Accessibility to count keys.")
                        .font(.system(size: 9)).foregroundStyle(.orange)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Listening diary (stays on this Mac)
struct DayLog: Codable { var seconds = 0.0; var top: [String: Double] = [:] }

final class DiaryStore: ObservableObject {
    @Published var days: [String: DayLog]
    private var last: Date?
    private var ticks = 0
    static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()

    init() {
        days = UserDefaults.standard.data(forKey: "spindle.diary")
            .flatMap { try? JSONDecoder().decode([String: DayLog].self, from: $0) } ?? [:]
    }

    func record(_ t: Track?) {
        guard let t else { last = nil; return }
        let now = Date()
        let dt = min(now.timeIntervalSince(last ?? now), 2)
        last = now
        guard dt > 0 else { return }
        let k = Self.fmt.string(from: now)
        var d = days[k] ?? DayLog()
        d.seconds += dt
        d.top["\(t.title) · \(t.artist)", default: 0] += dt
        days[k] = d
        ticks += 1
        if ticks % 15 == 0 { UserDefaults.standard.set(try? JSONEncoder().encode(days), forKey: "spindle.diary") }
    }

    var week: [(label: String, seconds: Double, key: String)] {
        (0..<7).reversed().map { i in
            let day = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
            let k = Self.fmt.string(from: day)
            return (day.formatted(.dateTime.weekday(.narrow)), days[k]?.seconds ?? 0, k)
        }
    }
    var topTrack: String? {
        var sum: [String: Double] = [:]
        for d in week { for (k, v) in days[d.key]?.top ?? [:] { sum[k, default: 0] += v } }
        return sum.max { $0.value < $1.value }?.key
    }
}

struct DiaryPage: View {
    @ObservedObject var diary: DiaryStore
    private func fmt(_ s: Double) -> String { let m = Int(s / 60); return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m" }
    var body: some View {
        let week = diary.week
        let peak = max(week.map(\.seconds).max() ?? 1, 1)
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(week, id: \.key) { d in
                    VStack(spacing: 3) {
                        Capsule().fill(.white.opacity(d.seconds > 0 ? 0.9 : 0.15))
                            .frame(width: 18, height: max(4, 50 * CGFloat(d.seconds / peak)))
                        Text(d.label).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }.animation(.spring(response: 0.5), value: peak)
            Text("\(fmt(week.map(\.seconds).reduce(0, +))) this week").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            if let t = diary.topTrack {
                Text("Most played: \(t)").font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Beat Glow (a pulsing light around the screen edge, tinted by the album cover)
final class GlowPanel: NSPanel {
    init(player: NowPlaying) {
        super.init(contentRect: NSScreen.main?.frame ?? .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: GlowView(player: player))
    }
}

struct GlowView: View {
    @ObservedObject var player: NowPlaying
    @State private var color = Color.white
    private let bpm = 100.0      // steady pulse; real audio reaction would need ScreenCaptureKit

    var body: some View {
        TimelineView(.animation) { tl in
            let p = (tl.date.timeIntervalSinceReferenceDate * bpm / 60).truncatingRemainder(dividingBy: 1)
            let k = exp(-4 * p)
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(color, lineWidth: 6 + 10 * k)
                .blur(radius: 10 + 14 * k)
                .opacity(0.25 + 0.6 * k)
        }
        .opacity(player.track == nil ? 0 : 1)
        .animation(.easeOut(duration: 0.4), value: player.track == nil)
        .ignoresSafeArea()
        .onChange(of: player.track?.artworkURL) { _, u in Task { await tint(u) } }
    }

    private func tint(_ url: URL?) async {
        guard let url, let (d, _) = try? await URLSession.shared.data(from: url),
              let img = NSImage(data: d), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        var px = [UInt8](repeating: 0, count: 4)
        px.withUnsafeMutableBytes { buf in
            let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.interpolationQuality = .medium
            ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let r = Double(px[0]) / 255, g = Double(px[1]) / 255, b = Double(px[2]) / 255
        let m = max(r, g, b, 1.0 / 255)                       // brighten dark covers so the glow stays visible
        await MainActor.run { color = Color(red: r / m, green: g / m, blue: b / m) }
    }
}
