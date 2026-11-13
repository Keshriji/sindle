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
        // Never ask here. AXIsProcessTrustedWithOptions(prompt:) blocks the calling thread while the
        // system consent sheet is up, and this runs during launch: that is what hangs the app.
        trusted = AXIsProcessTrusted()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, !e.isARepeat else { return }
            self.stamps.append(Date())
            if self.sounds { NSSound(named: "Tink")?.play() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.update() }
    }

    /// Asked for from the Typing page. The prompt itself runs off the main thread, so a slow TCC
    /// lookup can never freeze the app.
    func requestTrust() {
        DispatchQueue.global(qos: .userInitiated).async {
            let granted = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            DispatchQueue.main.async {
                self.trusted = granted
                if !granted, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
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
                    Button("Allow under Accessibility") { typing.requestTrust() }
                        .font(.system(size: 9)).foregroundStyle(.orange).buttonStyle(.plain)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Listening diary (stays on this Mac)
struct DayBar { let label: String; let seconds: Double; let key: String }
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

    var week: [DayBar] {
        (0..<7).reversed().map { i in
            let day = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
            let k = Self.fmt.string(from: day)
            return DayBar(label: day.formatted(.dateTime.weekday(.narrow)), seconds: days[k]?.seconds ?? 0, key: k)
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
    init(player: NowPlaying, audio: AudioLevel) {
        super.init(contentRect: NSScreen.main?.frame ?? .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: GlowView(player: player, audio: audio))
    }
}

struct GlowView: View {
    @ObservedObject var player: NowPlaying
    @ObservedObject var audio: AudioLevel
    @ObservedObject var s = SettingsStore.shared
    @State private var albumColor = Color.white

    private var visible: Bool { s.glowOnlyWhilePlaying ? player.track != nil : true }

    var body: some View {
        Group {
            if visible {
                // 30 fps rather than the display's refresh rate: this is a full-screen blurred
                // stroke, and re-rendering it 60-120 times a second was a large part of the load.
                TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    let p = (t * s.glowBPM / 60).truncatingRemainder(dividingBy: 1)
                    let live = tl.date.timeIntervalSince(audio.lastSample) < 1.5      // real audio if permission granted
                    let k = live ? audio.level : exp(-4 * p)
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(colour(t), lineWidth: s.glowThickness * (1 + 1.2 * k))
                        .blur(radius: s.glowBlur * (1 + 0.7 * k))
                        .opacity((0.25 + 0.6 * k) * s.glowIntensity)
                        .mask(edgeMask)
                }
            } else {
                Color.clear
            }
        }
        .animation(.easeOut(duration: 0.4), value: visible)
        .ignoresSafeArea()
        .onChange(of: player.track?.artworkURL) { _, u in Task { await tint(u) } }
    }

    private func colour(_ t: Double) -> Color {
        switch s.glowColorMode {
        case 1:  return Color(red: s.glowR, green: s.glowG, blue: s.glowB)
        case 2:  return Color(hue: (t * 0.08).truncatingRemainder(dividingBy: 1), saturation: 0.85, brightness: 1)
        default: return albumColor
        }
    }

    @ViewBuilder private var edgeMask: some View {
        switch s.glowEdges {
        case 1:  LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3))
        case 2:  LinearGradient(colors: [.white, .clear], startPoint: .bottom, endPoint: UnitPoint(x: 0.5, y: 0.7))
        case 3:  LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .clear, location: 0.18),
                                        .init(color: .clear, location: 0.82), .init(color: .white, location: 1)],
                                startPoint: .leading, endPoint: .trailing)
        default: Color.white
        }
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
        await MainActor.run { albumColor = Color(red: r / m, green: g / m, blue: b / m) }
    }
}
