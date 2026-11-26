import SwiftUI
import AppKit
import AVFoundation

// MARK: - the window

/// Frosted glass behind the whole window: whatever is on the desktop shows through, softened.
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

enum SettingsWindow {
    private static var win: NSWindow?

    static func show(player: NowPlaying, preview: @escaping () -> Void) {
        if win == nil {
            let host = NSHostingController(rootView: SettingsView(player: player, preview: preview))
            host.sizingOptions = []
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 920, height: 640))
            w.center()
            win = w
        }
        NSApp.activate(ignoringOtherApps: true)
        win?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - panes

enum Pane: String, CaseIterable, Identifiable {
    case nowPlaying = "Now Playing", island = "Island", lockScreen = "Lock Screen", desktop = "Desktop", lyrics = "Lyrics"
    case sound = "Sound", beatGlow = "Beat Glow", keys = "Keys", headphones = "Headphones"
    case wallpapers = "Wallpapers", faceUnlock = "Face Unlock", general = "General"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .nowPlaying: return "music.note"; case .island: return "capsule.fill"; case .lockScreen: return "lock.fill"
        case .desktop: return "macwindow"; case .lyrics: return "text.quote"; case .sound: return "speaker.wave.2.fill"
        case .beatGlow: return "light.max"; case .keys: return "keyboard"; case .headphones: return "headphones"
        case .wallpapers: return "photo.on.rectangle"; case .faceUnlock: return "faceid"; case .general: return "gearshape.fill"
        }
    }

    /// Words that find this pane in the search box.
    var keywords: String {
        switch self {
        case .nowPlaying: return "music spotify apple music safari chrome browser player cover"
        case .island: return "notch island shape floating glass hover click dashboard pages weather calendar timer notes tasks popups volume brightness charging focus"
        case .lockScreen: return "lock screen record cover card controls darkening title vinyl lens preview"
        case .desktop: return "desktop widget turntable sleeve aura lyrics card"
        case .lyrics: return "lyrics constellation big words lens terminal aura colour color background timing"
        case .sound: return "equalizer bars volume brightness edge sound"
        case .beatGlow: return "beat glow rim edges corners sides light thickness brightness motion colour lock"
        case .keys: return "keys typing key sounds keyboard click"
        case .headphones: return "headphones airpods battery bluetooth popup"
        case .wallpapers: return "wallpaper background paint"
        case .faceUnlock: return "face unlock camera private tabs"
        case .general: return "general login startup menu bar icon units fahrenheit clock sleep awake permissions camera accessibility location about"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var s = SettingsStore.shared
    @ObservedObject var face = FaceLock.shared
    @ObservedObject var player: NowPlaying
    var preview: () -> Void
    @State private var pane: Pane = .nowPlaying
    @State private var query = ""
    @State private var tint = Color.accentColor
    @State private var shown = false

    private let top: [Pane] = [.nowPlaying]
    private let features: [Pane] = [.island, .lockScreen, .desktop, .lyrics, .sound, .beatGlow, .keys, .headphones]
    private let bottom: [Pane] = [.wallpapers, .faceUnlock, .general]

    var body: some View {
        ZStack {
            VisualEffectView()
            background
            HStack(spacing: 0) {
                sidebar.frame(width: 240)
                detail
            }
        }
        .frame(width: 920, height: 640)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .tint(tint)
        .scaleEffect(shown ? 1 : 0.97)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { shown = true } }
        // The window takes its colour from the album that is playing, and melts into the next one with the song.
        .task(id: player.track?.artworkURL) {
            if let c = await AlbumColor.from(player.track?.artworkURL) {
                withAnimation(.easeInOut(duration: 1.4)) { tint = c }
            }
        }
    }

    /// Soft pools of the cover colour. The pool drifts a little with each pane, so changing pane feels like moving through the colour.
    private var background: some View {
        let index: Double = Double(Pane.allCases.firstIndex(of: pane) ?? 0)
        return ZStack {
            Color.black.opacity(0.28)
            LinearGradient(colors: [tint.opacity(0.46), tint.opacity(0.14), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [tint.opacity(0.34), .clear], center: UnitPoint(x: 0.88, y: 0.10 + index * 0.07),
                           startRadius: 0, endRadius: 460)
            RadialGradient(colors: [tint.opacity(0.22), .clear], center: UnitPoint(x: 0.10, y: 0.95 - index * 0.04),
                           startRadius: 0, endRadius: 380)
        }
        .animation(.easeInOut(duration: 0.9), value: pane)
    }

    // MARK: sidebar

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private func matches(_ p: Pane) -> Bool {
        guard searching else { return true }
        let q = query.lowercased()
        return p.rawValue.lowercased().contains(q) || p.keywords.contains(q)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("Search", text: $query).textFieldStyle(.plain).font(.system(size: 13))
                if searching {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.09)))
            .padding(.horizontal, 14).padding(.top, 46).padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(top.filter(matches)) { p in row(p) }
                    let feat = features.filter(matches)
                    if !feat.isEmpty {
                        Text("FEATURES").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.leading, 12).padding(.top, 14).padding(.bottom, 4)
                        ForEach(feat) { p in row(p) }
                    }
                }
                .padding(.horizontal, 10)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(bottom.filter(matches)) { p in row(p) }
            }
            .padding(.horizontal, 10).padding(.bottom, 14)
        }
    }

    private func status(_ p: Pane) -> String? {
        switch p {
        case .island: return s.islandOn ? "On" : "Off"
        case .lockScreen: return s.lockLyricsOn ? "On" : "Off"
        case .desktop: return s.widgetOn ? "On" : "Off"
        case .sound: return s.eqOn ? "On" : "Off"
        case .beatGlow: return s.glowOn ? "On" : "Off"
        case .keys: return s.keySoundsOn ? "On" : "Off"
        default: return nil
        }
    }

    private func row(_ p: Pane) -> some View {
        Button { withAnimation(.easeOut(duration: 0.2)) { pane = p } } label: {
            HStack(spacing: 10) {
                Image(systemName: p.icon).font(.system(size: 13, weight: .semibold)).frame(width: 20)
                Text(p.rawValue).font(.system(size: 13, weight: .medium))
                if p == .faceUnlock {
                    Text("BETA").font(.system(size: 8, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.16)))
                }
                Spacer()
                if let st = status(p) { Text(st).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            .foregroundStyle(pane == p ? Color.white : Color.white.opacity(0.78))
            .padding(.vertical, 7).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 9).fill(pane == p ? Color.white.opacity(0.16) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: detail

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: pane.icon).font(.system(size: 16, weight: .semibold))
                Text(pane.rawValue).font(.system(size: 20, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 28).padding(.top, 40).padding(.bottom, 14)
            ScrollView(showsIndicators: false) {
                content
                    .id(pane)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 14)), removal: .opacity))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28).padding(.bottom, 28)
            }
            .animation(.easeOut(duration: 0.24), value: pane)
        }
    }

    @ViewBuilder private var content: some View {
        switch pane {
        case .nowPlaying: nowPlayingPane
        case .island:     islandPane
        case .lockScreen: lockScreenPane
        case .desktop:    desktopPane
        case .lyrics:     lyricsPane
        case .sound:      soundPane
        case .beatGlow:   beatGlowPane
        case .keys:       keysPane
        case .headphones: headphonesPane
        case .wallpapers: wallpapersPane
        case .faceUnlock: faceUnlockPane
        case .general:    generalPane
        }
    }

    // MARK: building blocks

    private func asInt(_ b: Binding<Bool>) -> Binding<Int> {
        Binding<Int>(get: { b.wrappedValue ? 1 : 0 }, set: { b.wrappedValue = $0 == 1 })
    }

    private func card<C: View>(_ title: String? = nil, footer: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            }
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
            if let footer {
                Text(footer).font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
        }
        .padding(.bottom, 16)
    }

    private var divider: some View { Divider().opacity(0.18).padding(.leading, 14) }

    private func row<T: View>(_ title: String, _ subtitle: String? = nil, @ViewBuilder trailing: () -> T) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 12)
            trailing()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func toggleRow(_ title: String, _ subtitle: String? = nil, _ isOn: Binding<Bool>) -> some View {
        row(title, subtitle) { Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch) }
    }

    private func sliderRow(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ fmt: String = "%.2f") -> some View {
        row(title) {
            HStack(spacing: 10) {
                Slider(value: value, in: range).frame(width: 220)
                Text(String(format: fmt, value.wrappedValue)).font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
            }
        }
    }

    /// A row of rounded chips, one of them selected.
    private func chipsRow(_ title: String, _ options: [String], _ selection: Binding<Int>) -> some View {
        row(title) {
            HStack(spacing: 6) {
                ForEach(0..<options.count, id: \.self) { i in
                    Button { withAnimation(.easeOut(duration: 0.15)) { selection.wrappedValue = i } } label: {
                        Text(options[i]).font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 11).padding(.vertical, 5)
                            .background(Capsule().fill(selection.wrappedValue == i ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(0.10))))
                            .foregroundStyle(selection.wrappedValue == i ? Color.white : Color.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func buttonRow(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title).font(.system(size: 13)).foregroundStyle(.tint); Spacer() }
                .padding(.horizontal, 14).padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private struct Tile {
        let title: String
        let caption: String
        let preview: AnyView
    }

    /// Pictures to choose from, the chosen one outlined in the cover colour.
    private func tiles(_ items: [Tile], _ selection: Binding<Int>, width: CGFloat = 118) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: width), spacing: 12)], alignment: .leading, spacing: 12) {
            ForEach(0..<items.count, id: \.self) { i in
                Button { withAnimation(.easeOut(duration: 0.18)) { selection.wrappedValue = i } } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        items[i].preview
                            .frame(height: 66)
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(selection.wrappedValue == i ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(0.10)),
                                              lineWidth: selection.wrappedValue == i ? 2.5 : 1))
                        Text(items[i].title).font(.system(size: 12, weight: .semibold))
                        Text(items[i].caption).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }

    private func quickTile(_ icon: String, _ title: String, _ sub: String, _ isOn: Binding<Bool>) -> some View {
        Button { withAnimation(.easeOut(duration: 0.18)) { isOn.wrappedValue.toggle() } } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).frame(width: 34, height: 34)
                    .background(Circle().fill(isOn.wrappedValue ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(0.12))))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(sub).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(isOn.wrappedValue ? 0.12 : 0.06)))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(isOn.wrappedValue ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(0.08)), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
    }

    private func colourPicker(_ title: String, _ r: Binding<Double>, _ g: Binding<Double>, _ b: Binding<Double>) -> some View {
        row(title) {
            ColorPicker("", selection: Binding<Color>(
                get: { Color(red: r.wrappedValue, green: g.wrappedValue, blue: b.wrappedValue) },
                set: { c in
                    let n = NSColor(c).usingColorSpace(.sRGB) ?? .white
                    r.wrappedValue = Double(n.redComponent); g.wrappedValue = Double(n.greenComponent); b.wrappedValue = Double(n.blueComponent)
                })).labelsHidden()
        }
    }

    // MARK: Now Playing

    private var nowPlayingPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            card {
                HStack(spacing: 14) {
                    AsyncImage(url: player.track?.artworkURL) { $0.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.1) }
                        .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.track?.title ?? "Nothing playing").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text(player.track.map { "\($0.artist) · \($0.source)" } ?? "Play something in Spotify, Music or a browser")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    HStack(spacing: 18) {
                        Button { player.send("previous track") } label: { Image(systemName: "backward.fill") }
                        Button { player.send("playpause") } label: { Image(systemName: (player.track?.isPlaying ?? false) ? "pause.fill" : "play.fill").font(.system(size: 20)) }
                        Button { player.send("next track") } label: { Image(systemName: "forward.fill") }
                    }
                    .buttonStyle(.plain).font(.system(size: 15))
                }
                .padding(14)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                quickTile("lock.fill", "Lock Screen", "Vinyl and player", $s.lockLyricsOn)
                quickTile("light.max", "Beat Glow", "Screen edge", $s.glowOn)
                quickTile("capsule.fill", "Notch Island", "Compact", $s.islandOn)
                quickTile("opticaldisc", "Desktop", "Turntable", $s.widgetOn)
            }
            .padding(.bottom, 16)
            card("Players") {
                row("Spotify and Apple Music", "Read and controlled through macOS") { Text("Always on").font(.system(size: 12)).foregroundStyle(.secondary) }
                divider
                toggleRow("Videos in the browser", "Safari, Chrome, Brave and Edge: YouTube, Spotify Web, SoundCloud and more", $s.browsersOn)
            }
            card(footer: "In Safari, turn on Develop, then Allow JavaScript from Apple Events. In Chrome, Brave and Edge, turn on View, Developer, Allow JavaScript from Apple Events. macOS then asks once to let Spindle control each browser.") { EmptyView() }
        }
    }

    // MARK: Island

    private var islandPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            card("Shape") {
                tiles([
                    Tile(title: "Classic", caption: "Round the notch, from the top edge", preview: AnyView(IslandShapePreview(floating: false))),
                    Tile(title: "Floating", caption: "An oval under the top edge", preview: AnyView(IslandShapePreview(floating: true)))
                ], asInt($s.floatingIsland), width: 200)
            }
            card("Open") {
                chipsRow("Open with", ["Hover", "Click"], asInt($s.openOnClick))
                divider
                toggleRow("Wide dashboard straight away", "Music, mirror and weather together", $s.bigIsland)
                divider
                toggleRow("Fade out when nothing is playing", nil, $s.hideWhenIdle)
                divider
                toggleRow("Keep it open", "It will not close when you move away", $s.keepOpen)
            }
            card("Look") {
                chipsRow("Background", ["Black", "Glass"], asInt($s.glassStyle))
                if s.glassStyle {
                    divider
                    chipsRow("Frost", ["Light", "Medium", "Heavy", "Solid"], $s.glassMaterial)
                    divider
                    sliderRow("Darkness", $s.glassTint, 0...0.8)
                }
                divider
                chipsRow("Cover", ["Big cover", "Record"], asInt($s.turntable))
                divider
                sliderRow("Size", $s.islandScale, 0.8...1.3)
                divider
                sliderRow("Animation speed", $s.animSpeed, 0.6...2.0)
            }
            card("Pages", footer: "The icons down the right edge of the wide dashboard.") {
                ForEach(Array(RailItem.allCases.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { divider }
                    toggleRow(item.title, nil, Binding(get: { s.railOn(item.key) }, set: { s.setRail(item.key, $0) }))
                }
            }
            card("Moments", footer: "Little pop-ups that slide out either side of the notch.") {
                toggleRow("Pop-ups", "The master switch for the ones below", $s.toastsOn)
                divider
                toggleRow("Volume and brightness", nil, $s.toastVolume)
                divider
                toggleRow("Charging", nil, $s.toastCharging)
                divider
                toggleRow("Focus", nil, $s.toastFocus)
                divider
                toggleRow("Headphones", nil, $s.toastHeadphones)
            }
        }
    }

    // MARK: Lock Screen

    private var lockScreenPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            card("Lock screen") {
                toggleRow("Show on the lock screen", "Record, cover and lyrics when the Mac locks", $s.lockLyricsOn)
                divider
                chipsRow("Starts with", ["Record", "Cover", "Lyrics"], $s.lockStage)
                divider
                toggleRow("Play, pause and skip in the card", nil, $s.lockControlsOn)
                divider
                toggleRow("Click when the Mac locks and unlocks", nil, $s.lockSoundsOn)
            }
            card("Look") {
                toggleRow("Small record in cover and lyrics", nil, $s.lockRecordOn)
                divider
                sliderRow("Record size", $s.lockRecordSize, 100...240, "%.0f")
                divider
                sliderRow("Screen darkening", $s.lockDim, 0...1)
                divider
                toggleRow("Song title and artist", nil, $s.lockTitleOn)
                divider
                toggleRow("Next line", nil, $s.lockNextLineOn)
                divider
                toggleRow("Song title down the left edge", "Constellation style", $s.lockVerticalTitle)
                divider
                chipsRow("Card", ["Liquid", "Clear", "Solid"], $s.lockGlass)
                divider
                sliderRow("Lens bend", $s.lensBend, 0...1)
            }
            card("Try it", footer: "The record turns under the clock. Click it to lift the cover, click the cover to fill the screen with lyrics, click the card to go back. Play a song first.") {
                buttonRow("Preview for 10 seconds", preview)
            }
        }
    }

    // MARK: Desktop

    private var desktopPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            card("Widget") {
                toggleRow("Show the desktop widget", "Click it to switch style, drag it to move it", $s.widgetOn)
                divider
                tiles([
                    Tile(title: "Turntable", caption: "A record turning on a deck", preview: AnyView(SymbolPreview("opticaldisc"))),
                    Tile(title: "Record sleeve", caption: "The record slides out of its sleeve", preview: AnyView(SymbolPreview("square.stack"))),
                    Tile(title: "Aura", caption: "The cover as soft light", preview: AnyView(SymbolPreview("circle.hexagongrid.fill")))
                ], $s.widgetStyle)
            }
            card("Lyrics") {
                toggleRow("Lyrics on the desktop", "A card in your chosen lyric style. Drag it anywhere", $s.desktopLyricsOn)
            }
        }
    }

    // MARK: Lyrics

    private var lyricStyleTiles: [Tile] {
        [
            Tile(title: "Constellation", caption: "Words join into a network", preview: AnyView(LyricStylePreview(style: 0))),
            Tile(title: "Big Words", caption: "One huge word at a time", preview: AnyView(LyricStylePreview(style: 1))),
            Tile(title: "Lens", caption: "The line in focus", preview: AnyView(LyricStylePreview(style: 2))),
            Tile(title: "Terminal", caption: "Typed out in green", preview: AnyView(LyricStylePreview(style: 3))),
            Tile(title: "Aura", caption: "A turning drum of words", preview: AnyView(LyricStylePreview(style: 4)))
        ]
    }

    private struct Swatch: Identifiable {
        let id: String
        let colour: Color
        let mode: Int
        let rgb: (Double, Double, Double)
    }

    private let swatches: [Swatch] = [
        Swatch(id: "White", colour: .white, mode: 0, rgb: (1, 1, 1)),
        Swatch(id: "Cover", colour: Color(white: 0.5), mode: 1, rgb: (1, 1, 1)),
        Swatch(id: "Red", colour: Color(red: 1, green: 0.27, blue: 0.23), mode: 2, rgb: (1, 0.27, 0.23)),
        Swatch(id: "Orange", colour: Color(red: 1, green: 0.62, blue: 0.04), mode: 2, rgb: (1, 0.62, 0.04)),
        Swatch(id: "Yellow", colour: Color(red: 1, green: 0.84, blue: 0.04), mode: 2, rgb: (1, 0.84, 0.04)),
        Swatch(id: "Green", colour: Color(red: 0.2, green: 0.84, blue: 0.29), mode: 2, rgb: (0.2, 0.84, 0.29)),
        Swatch(id: "Teal", colour: Color(red: 0.19, green: 0.82, blue: 0.78), mode: 2, rgb: (0.19, 0.82, 0.78)),
        Swatch(id: "Blue", colour: Color(red: 0.04, green: 0.52, blue: 1), mode: 2, rgb: (0.04, 0.52, 1)),
        Swatch(id: "Purple", colour: Color(red: 0.75, green: 0.35, blue: 0.95), mode: 2, rgb: (0.75, 0.35, 0.95)),
        Swatch(id: "Pink", colour: Color(red: 1, green: 0.18, blue: 0.33), mode: 2, rgb: (1, 0.18, 0.33)),
        Swatch(id: "Rainbow", colour: Color(white: 0.5), mode: 3, rgb: (1, 1, 1))
    ]

    private func swatchSelected(_ w: Swatch) -> Bool {
        if w.mode != 2 { return s.lyricColorMode == w.mode }
        guard s.lyricColorMode == 2 else { return false }
        return abs(s.lyricR - w.rgb.0) < 0.02 && abs(s.lyricG - w.rgb.1) < 0.02 && abs(s.lyricB - w.rgb.2) < 0.02
    }

    private var swatchRow: some View {
        HStack(spacing: 9) {
            ForEach(swatches) { w in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        s.lyricColorMode = w.mode
                        if w.mode == 2 { s.lyricR = w.rgb.0; s.lyricG = w.rgb.1; s.lyricB = w.rgb.2 }
                    }
                } label: {
                    ZStack {
                        if w.id == "Rainbow" {
                            Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center))
                        } else if w.id == "Cover" {
                            Circle().fill(tint)
                        } else {
                            Circle().fill(w.colour)
                        }
                        if swatchSelected(w) {
                            Circle().strokeBorder(Color.white, lineWidth: 2.5).padding(-3)
                        }
                    }
                    .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(w.id)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var lyricsPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            card("Style", footer: styleNote(s.lyricStyle)) {
                tiles(lyricStyleTiles, $s.lyricStyle)
            }
            card("Where") {
                toggleRow("Open when locked", nil, $s.lockLyricsOn)
                divider
                toggleRow("On the desktop", nil, $s.desktopLyricsOn)
                divider
                toggleRow("Keep the screen on while lyrics play", nil, $s.screenKeeper)
            }
            card("Colour", footer: "White, the album's colour, one of your own, or a different colour for every word.") {
                swatchRow
                if s.lyricColorMode == 2 {
                    divider
                    colourPicker("Custom colour", $s.lyricR, $s.lyricG, $s.lyricB)
                }
            }
            card("Background") {
                chipsRow("Behind the words", ["Dark", "Album cover"], $s.lyricBackground)
                divider
                toggleRow("Constellation behind Aura and Big Words", nil, $s.constellationBehind)
                divider
                toggleRow("Twinkling stars", nil, $s.starsOn)
            }
            card("Timing", footer: "Lyrics come from LRCLIB when a synced version exists.") {
                sliderRow("Seconds early", $s.lyricOffset, -2...2)
                divider
                sliderRow("Scatter (desktop card)", $s.lyricScatter, 0...1)
            }
        }
    }

    private func styleNote(_ style: Int) -> String {
        switch style {
        case 0:  return "Constellation: every word of the song becomes a point; thin lines join them into a growing network, with a ring on the word being sung. Fills the lock screen."
        case 1:  return "Big Words: the word being sung is huge, the one before it small above, the next one small and italic below, with a little picture beside words like \"lights\" or \"down\". Fills the lock screen."
        case 2:  return "Lens: the current line is sharp, the lines around it blur away."
        case 3:  return "Terminal: the line is typed out in green with a blinking cursor."
        default: return "Aura: one huge word at a time on a turning 3D drum, over a dark heart ringed with the cover's colours. Fills the lock screen."
        }
    }

    // MARK: Sound

    private var soundPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            card("Equalizer", footer: "Moves with the real sound once macOS lets Spindle hear system audio. Until then the bars play a gentle demo pattern.") {
                toggleRow("Show the equalizer in the island", nil, $s.eqOn)
                divider
                row("Bars") { Stepper("\(s.eqBars)", value: $s.eqBars, in: 3...8) }
                divider
                chipsRow("Colour", ["White", "Rainbow"], $s.eqColorMode)
            }
            card("Edge bars") {
                toggleRow("Volume and brightness on the screen edges", "Hover a bar to widen it, drag to change", $s.edgeSlidersOn)
            }
        }
    }

    // MARK: Beat Glow

    private var glowStyleTiles: [Tile] {
        [
            Tile(title: "Rim", caption: "A line of light round the whole screen", preview: AnyView(GlowStylePreview(style: 0))),
            Tile(title: "Edges", caption: "Light along every edge", preview: AnyView(GlowStylePreview(style: 1))),
            Tile(title: "Corners", caption: "Out of the four corners", preview: AnyView(GlowStylePreview(style: 2))),
            Tile(title: "Sides", caption: "Left and right only", preview: AnyView(GlowStylePreview(style: 3)))
        ]
    }

    private var beatGlowPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            card(footer: "Light on your screen, flicking to the beat.") {
                toggleRow("Beat Glow", nil, $s.glowOn)
                divider
                toggleRow("Only while music is playing", nil, $s.glowOnlyWhilePlaying)
            }
            card("Style") { tiles(glowStyleTiles, $s.glowStyle, width: 130) }
            card("Light") {
                sliderRow("Thickness", $s.glowThickness, 2...24, "%.0f")
                divider
                sliderRow("Brightness", $s.glowIntensity, 0.2...1)
                divider
                sliderRow("Softness", $s.glowBlur, 4...40, "%.0f")
                divider
                chipsRow("Motion", ["To the beat", "Steady"], $s.glowMotion)
                if s.glowMotion == 1 {
                    divider
                    sliderRow("Pulse (BPM)", $s.glowBPM, 60...180, "%.0f")
                }
                divider
                chipsRow("Colours", ["From the album", "My colour", "Rainbow"], $s.glowColorMode)
                if s.glowColorMode == 1 {
                    divider
                    colourPicker("My colour", $s.glowR, $s.glowG, $s.glowB)
                }
            }
            card(footer: "The light reacts to what plays on this Mac. It only listens for the beat: nothing is recorded or sent anywhere.") {
                toggleRow("On the lock screen", nil, $s.glowOnLock)
                divider
                buttonRow("Reset Beat Glow") { s.resetGlow() }
            }
        }
    }

    // MARK: Keys

    private var keysPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            card("Key sounds", footer: "Counts keys system-wide, so it needs Accessibility. Nothing you type is recorded.") {
                toggleRow("A click on every key press", nil, $s.keySoundsOn)
                divider
                chipsRow("Set", ["Office", "Retro", "Soft"], $s.keySoundSet)
                divider
                sliderRow("Volume", $s.keySoundVolume, 0...1)
            }
        }
    }

    // MARK: Headphones

    private var headphonesPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            card("Headphones", footer: "Battery for each earbud and the case shows in the island's Headphones page.") {
                toggleRow("Pop-up when they connect", nil, $s.toastHeadphones)
                divider
                toggleRow("Headphones page in the dashboard", nil, Binding(get: { s.railOn("status") }, set: { s.setRail("status", $0) }))
            }
        }
    }

    // MARK: Wallpapers

    private var wallpapersPane: some View {
        card("Desktop wallpaper", footer: "Tap one to set it on every screen.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 12) {
                ForEach(Walls.all) { w in
                    Button { Walls.apply(w) } label: {
                        VStack(spacing: 4) {
                            Image(nsImage: Walls.thumb(w)).resizable().scaledToFill()
                                .frame(width: 104, height: 64).clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(w.name).font(.system(size: 11))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
    }

    // MARK: Face Unlock

    private var faceUnlockPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            card(footer: "Turn it on to hide Tray, Notes, Tasks and Diary until the camera knows it is you. A convenience lock, not strong security: a photo of you might fool it. It does not unlock your Mac. Touch ID or your password always works.") {
                toggleRow("Lock private tabs until it's you", nil, $s.faceLockOn)
                divider
                buttonRow(face.enrolled > 0 ? "Redo Face Unlock" : "Set up Face Unlock") { face.startEnrol() }
                if face.enrolled > 0 {
                    divider
                    buttonRow("Remove my face data") { face.resetFace() }
                }
                if !face.status.isEmpty {
                    divider
                    note(face.status)
                }
            }
            card("Strictness", footer: "Lower is stricter. The score shown while it looks for you tells you where to set this.") {
                sliderRow("Needs under", $face.threshold, 0.2...0.9)
            }
        }
    }

    // MARK: General

    private func permRow(_ title: String, _ detail: String, _ granted: Bool?, _ pane: String) -> some View {
        row(title, detail) {
            HStack(spacing: 8) {
                Image(systemName: granted == true ? "checkmark.circle.fill" : (granted == false ? "xmark.circle" : "questionmark.circle"))
                    .foregroundStyle(granted == true ? Color.green : Color.secondary)
                Button("Open") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
                }
            }
        }
    }

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            card("Show") {
                toggleRow("Dynamic island", nil, $s.islandOn)
                divider
                toggleRow("Lock screen lyrics", nil, $s.lockLyricsOn)
                divider
                toggleRow("Beat Glow", nil, $s.glowOn)
                divider
                toggleRow("Desktop widget", nil, $s.widgetOn)
                divider
                toggleRow("Lyrics on the desktop", nil, $s.desktopLyricsOn)
                divider
                toggleRow("Volume and brightness edge bars", nil, $s.edgeSlidersOn)
            }
            card("Startup", footer: "If you hide the menu bar icon, open Spindle again from Applications to bring these settings back.") {
                toggleRow("Open Spindle at login", nil, $s.launchAtLogin)
                divider
                toggleRow("Menu bar icon", nil, $s.showMenuIcon)
            }
            card("Units and clock") {
                toggleRow("Temperature in °F", nil, $s.fahrenheit)
                divider
                chipsRow("Clock font", ["Rounded", "Serif", "Mono"], $s.clockFont)
            }
            card("Permissions", footer: "Builds from GitHub keep the same signature, so a permission you allow stays allowed. Reopen this window to refresh the ticks.") {
                permRow("Audio capture", "Equalizer and Beat Glow follow the music. Asked once.", nil, "Privacy_ScreenCapture")
                divider
                permRow("Accessibility", "Typing speed and key sounds", AXIsProcessTrusted(), "Privacy_Accessibility")
                divider
                permRow("Camera", "Mirror and Face Unlock", AVCaptureDevice.authorizationStatus(for: .video) == .authorized, "Privacy_Camera")
                divider
                permRow("Automation", "Spotify, Music, Safari and Chrome", nil, "Privacy_Automation")
                divider
                permRow("Location", "Weather. Without it your approximate city is used", nil, "Privacy_LocationServices")
                divider
                permRow("Full Disk Access", "Focus mode pop-up", nil, "Privacy_AllFiles")
            }
            card("About", footer: "Spindle is an independent app and isn't affiliated with Spotify, Apple or Google. Weather: MET Norway. Lyrics: LRCLIB.") {
                row("Version") { Text("0.1.0").foregroundStyle(.secondary) }
            }
        }
    }
}

// MARK: - little pictures for the tiles

struct SymbolPreview: View {
    let name: String
    init(_ name: String) { self.name = name }
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom)
            Image(systemName: name).font(.system(size: 26)).foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// The two island shapes: attached to the notch, or floating under the top edge.
struct IslandShapePreview: View {
    let floating: Bool
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(white: 0.16), Color(white: 0.07)], startPoint: .top, endPoint: .bottom)
            RoundedRectangle(cornerRadius: 3).fill(Color.black).frame(width: 34, height: 7).offset(y: 0)
            if floating {
                Capsule().fill(Color.black).frame(width: 66, height: 15).overlay(Capsule().strokeBorder(Color.white.opacity(0.18)))
                    .offset(y: 16)
            } else {
                UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10).fill(Color.black)
                    .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10).strokeBorder(Color.white.opacity(0.18)))
                    .frame(width: 72, height: 24)
            }
        }
    }
}

/// A miniature of each lyric style, drawn rather than animated.
struct LyricStylePreview: View {
    let style: Int
    var body: some View {
        ZStack {
            Color.black
            switch style {
            case 0:
                Canvas { ctx, size in
                    let pts: [CGPoint] = [CGPoint(x: 0.12, y: 0.65), CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.5, y: 0.6),
                                          CGPoint(x: 0.68, y: 0.28), CGPoint(x: 0.88, y: 0.55)]
                    var path = Path()
                    for (i, p) in pts.enumerated() {
                        let pt = CGPoint(x: p.x * size.width, y: p.y * size.height)
                        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                    ctx.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 0.8)
                    for p in pts {
                        let pt = CGPoint(x: p.x * size.width, y: p.y * size.height)
                        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2, y: pt.y - 2, width: 4, height: 4)), with: .color(.white))
                    }
                    ctx.stroke(Path(ellipseIn: CGRect(x: pts[3].x * size.width - 6, y: pts[3].y * size.height - 6, width: 12, height: 12)),
                               with: .color(.white), lineWidth: 1)
                }
            case 1:
                VStack(spacing: 1) {
                    Text("the").font(.system(size: 7, weight: .bold)).foregroundStyle(.white.opacity(0.5))
                    Text("Big").font(.system(size: 24, weight: .heavy)).foregroundStyle(.tint)
                    Text("words").font(.system(size: 8, weight: .bold)).italic().foregroundStyle(.white)
                }
            case 2:
                VStack(spacing: 2) {
                    Text("line before").font(.system(size: 8)).foregroundStyle(.white.opacity(0.5)).blur(radius: 1.5)
                    Text("In focus").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                    Text("line after").font(.system(size: 8)).foregroundStyle(.white.opacity(0.5)).blur(radius: 1.5)
                }
            case 3:
                Text("> let the needle_").font(.system(size: 9, design: .monospaced)).foregroundStyle(.green)
            default:
                ZStack {
                    RadialGradient(colors: [.black, .black, Color.accentColor.opacity(0.55)], center: .center, startRadius: 4, endRadius: 60)
                    Text("AURA").font(.system(size: 22, weight: .black)).foregroundStyle(.white)
                }
            }
        }
    }
}

/// A miniature of each Beat Glow style.
struct GlowStylePreview: View {
    let style: Int
    var body: some View {
        ZStack {
            Color.black
            switch style {
            case 0:
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color(red: 1, green: 0.3, blue: 0.4), lineWidth: 1.6)
                    .shadow(color: Color(red: 1, green: 0.3, blue: 0.4), radius: 4).padding(4)
            case 1:
                ZStack {
                    LinearGradient(colors: [Color(red: 1, green: 0.3, blue: 0.4).opacity(0.7), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35))
                    LinearGradient(colors: [Color(red: 1, green: 0.3, blue: 0.4).opacity(0.7), .clear], startPoint: .bottom, endPoint: UnitPoint(x: 0.5, y: 0.65))
                    LinearGradient(colors: [Color(red: 1, green: 0.3, blue: 0.4).opacity(0.7), .clear], startPoint: .leading, endPoint: UnitPoint(x: 0.3, y: 0.5))
                    LinearGradient(colors: [Color(red: 1, green: 0.3, blue: 0.4).opacity(0.7), .clear], startPoint: .trailing, endPoint: UnitPoint(x: 0.7, y: 0.5))
                }
            case 2:
                ZStack {
                    ForEach(0..<4, id: \.self) { i in
                        RadialGradient(colors: [Color(red: 1, green: 0.3, blue: 0.4).opacity(0.8), .clear],
                                       center: UnitPoint(x: i % 2 == 0 ? 0 : 1, y: i < 2 ? 0 : 1), startRadius: 0, endRadius: 34)
                    }
                }
            default:
                HStack {
                    LinearGradient(colors: [Color(red: 1, green: 0.3, blue: 0.4).opacity(0.8), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 30)
                    Spacer()
                    LinearGradient(colors: [Color(red: 1, green: 0.3, blue: 0.4).opacity(0.8), .clear], startPoint: .trailing, endPoint: .leading).frame(width: 30)
                }
            }
        }
    }
}
