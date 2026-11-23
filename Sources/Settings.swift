import SwiftUI
import AppKit
import ServiceManagement
import AVFoundation

/// Every option, saved on this Mac.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private static func flag(_ k: String, _ d: Bool) -> Bool { UserDefaults.standard.object(forKey: "s." + k) as? Bool ?? d }
    private static func num(_ k: String, _ d: Double) -> Double { UserDefaults.standard.object(forKey: "s." + k) as? Double ?? d }
    private static func int(_ k: String, _ d: Int) -> Int { UserDefaults.standard.object(forKey: "s." + k) as? Int ?? d }
    private func put(_ k: String, _ v: Any) { UserDefaults.standard.set(v, forKey: "s." + k) }

    // Show / hide
    @Published var islandOn: Bool       { didSet { put("islandOn", islandOn) } }
    @Published var toastsOn: Bool       { didSet { put("toastsOn", toastsOn) } }
    @Published var edgeSlidersOn: Bool  { didSet { put("edgeSlidersOn", edgeSlidersOn) } }
    @Published var widgetOn: Bool       { didSet { put("widgetOn", widgetOn) } }
    @Published var desktopLyricsOn: Bool { didSet { put("desktopLyricsOn", desktopLyricsOn) } }
    @Published var glowOn: Bool         { didSet { put("glowOn", glowOn) } }
    @Published var lockLyricsOn: Bool   { didSet { put("lockLyricsOn", lockLyricsOn) } }
    // Island
    @Published var floatingIsland: Bool { didSet { put("floatingIsland", floatingIsland) } }
    @Published var openOnClick: Bool    { didSet { put("openOnClick", openOnClick) } }
    @Published var hideWhenIdle: Bool   { didSet { put("hideWhenIdle", hideWhenIdle) } }
    @Published var glassStyle: Bool     { didSet { put("glassStyle", glassStyle) } }
    @Published var islandScale: Double  { didSet { put("islandScale", islandScale) } }
    @Published var animSpeed: Double    { didSet { put("animSpeed", animSpeed) } }
    // Lyrics / lock / desktop
    @Published var lyricStyle: Int      { didSet { put("lyricStyle", lyricStyle) } }
    @Published var starsOn: Bool        { didSet { put("starsOn", starsOn) } }
    @Published var lockRecordOn: Bool   { didSet { put("lockRecordOn", lockRecordOn) } }
    @Published var widgetStyle: Int     { didSet { put("widgetStyle", widgetStyle) } }
    // Needle-parity extras
    @Published var bigIsland: Bool      { didSet { put("bigIsland", bigIsland) } }
    @Published var turntable: Bool      { didSet { put("turntable", turntable) } }
    @Published var clockFont: Int       { didSet { put("clockFont", clockFont) } }
    @Published var screenKeeper: Bool   { didSet { put("screenKeeper", screenKeeper) } }
    // Key sounds
    @Published var keySoundsOn: Bool    { didSet { put("keySoundsOn", keySoundsOn) } }
    @Published var keySoundSet: Int     { didSet { put("keySoundSet", keySoundSet) } }
    @Published var keySoundVolume: Double { didSet { put("keySoundVolume", keySoundVolume) } }
    // Equalizer, glass, lock screen, lyrics look
    @Published var eqOn: Bool           { didSet { put("eqOn", eqOn) } }
    @Published var eqBars: Int          { didSet { put("eqBars", eqBars) } }
    @Published var eqColorMode: Int     { didSet { put("eqColorMode", eqColorMode) } }       // 0 white, 1 rainbow
    @Published var eqSensitivity: Double { didSet { put("eqSensitivity", eqSensitivity) } }
    @Published var glassMaterial: Int   { didSet { put("glassMaterial", glassMaterial) } }
    @Published var glassTint: Double    { didSet { put("glassTint", glassTint) } }
    @Published var keepOpen: Bool       { didSet { put("keepOpen", keepOpen) } }
    @Published var lockStage: Int       { didSet { put("lockStage", lockStage) } }           // 0 record, 1 cover, 2 lyrics
    @Published var lockDim: Double      { didSet { put("lockDim", lockDim) } }
    @Published var lockRecordSize: Double { didSet { put("lockRecordSize", lockRecordSize) } }
    @Published var lockTitleOn: Bool    { didSet { put("lockTitleOn", lockTitleOn) } }
    @Published var lockNextLineOn: Bool { didSet { put("lockNextLineOn", lockNextLineOn) } }
    @Published var lockVerticalTitle: Bool { didSet { put("lockVerticalTitle", lockVerticalTitle) } }
    @Published var constellationBehind: Bool { didSet { put("constellationBehind", constellationBehind) } }
    @Published var lockControlsOn: Bool { didSet { put("lockControlsOn", lockControlsOn) } }
    @Published var lockSoundsOn: Bool   { didSet { put("lockSoundsOn", lockSoundsOn) } }
    @Published var lockGlass: Int       { didSet { put("lockGlass", lockGlass) } }           // 0 liquid, 1 clear, 2 off
    @Published var lensBend: Double     { didSet { put("lensBend", lensBend) } }             // how much the lens bends the lines beside it
    @Published var lyricBackground: Int { didSet { put("lyricBackground", lyricBackground) } } // 0 dark, 1 album blur
    @Published var lyricScatter: Double { didSet { put("lyricScatter", lyricScatter) } }
    @Published var lyricOffset: Double  { didSet { put("lyricOffset", lyricOffset) } }       // seconds the lyrics run early
    @Published var lyricColorMode: Int  { didSet { put("lyricColorMode", lyricColorMode) } }   // 0 white, 1 album, 2 custom
    @Published var lyricR: Double       { didSet { put("lyricR", lyricR) } }
    @Published var lyricG: Double       { didSet { put("lyricG", lyricG) } }
    @Published var lyricB: Double       { didSet { put("lyricB", lyricB) } }
    // Beat Glow
    @Published var glowOnlyWhilePlaying: Bool { didSet { put("glowOnlyWhilePlaying", glowOnlyWhilePlaying) } }
    @Published var glowColorMode: Int   { didSet { put("glowColorMode", glowColorMode) } }   // 0 album, 1 custom, 2 rainbow
    @Published var glowR: Double        { didSet { put("glowR", glowR) } }
    @Published var glowG: Double        { didSet { put("glowG", glowG) } }
    @Published var glowB: Double        { didSet { put("glowB", glowB) } }
    @Published var glowEdges: Int       { didSet { put("glowEdges", glowEdges) } }           // 0 all, 1 top, 2 bottom, 3 sides
    @Published var glowIntensity: Double { didSet { put("glowIntensity", glowIntensity) } }
    @Published var glowThickness: Double { didSet { put("glowThickness", glowThickness) } }
    @Published var glowBlur: Double     { didSet { put("glowBlur", glowBlur) } }
    @Published var glowBPM: Double      { didSet { put("glowBPM", glowBPM) } }
    // Other
    @Published var faceLockOn: Bool     { didSet { put("faceLockOn", faceLockOn) } }
    @Published var fahrenheit: Bool     { didSet { put("fahrenheit", fahrenheit) } }
    @Published var showMenuIcon: Bool   { didSet { put("showMenuIcon", showMenuIcon) } }
    @Published var browsersOn: Bool     { didSet { put("browsersOn", browsersOn) } }
    @Published var launchAtLogin: Bool  {
        didSet { if launchAtLogin { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() } }
    }

    private init() {
        islandOn = Self.flag("islandOn", true); toastsOn = Self.flag("toastsOn", true)
        edgeSlidersOn = Self.flag("edgeSlidersOn", true); widgetOn = Self.flag("widgetOn", true)
        desktopLyricsOn = Self.flag("desktopLyricsOn", false); glowOn = Self.flag("glowOn", true)
        lockLyricsOn = Self.flag("lockLyricsOn", true)
        floatingIsland = Self.flag("floatingIsland", false); openOnClick = Self.flag("openOnClick", true)
        hideWhenIdle = Self.flag("hideWhenIdle", false); glassStyle = Self.flag("glassStyle", false)
        islandScale = Self.num("islandScale", 1); animSpeed = Self.num("animSpeed", 1)
        lyricStyle = Self.int("lyricStyle", 0)
        starsOn = Self.flag("starsOn", true); lockRecordOn = Self.flag("lockRecordOn", true)
        widgetStyle = Self.int("widgetStyle", 0)
        bigIsland = Self.flag("bigIsland", false); turntable = Self.flag("turntable", true)
        clockFont = Self.int("clockFont", 0); screenKeeper = Self.flag("screenKeeper", false)
        keySoundsOn = Self.flag("keySoundsOn", false); keySoundSet = Self.int("keySoundSet", 0)
        keySoundVolume = Self.num("keySoundVolume", 0.5)
        glowOnlyWhilePlaying = Self.flag("glowOnlyWhilePlaying", true); glowColorMode = Self.int("glowColorMode", 0)
        glowR = Self.num("glowR", 1); glowG = Self.num("glowG", 0.4); glowB = Self.num("glowB", 0.3)
        glowEdges = Self.int("glowEdges", 0); glowIntensity = Self.num("glowIntensity", 1)
        glowThickness = Self.num("glowThickness", 6); glowBlur = Self.num("glowBlur", 12)
        
        glowBPM = Self.num("glowBPM", 100)
        eqOn = Self.flag("eqOn", true); eqBars = Self.int("eqBars", 5); eqColorMode = Self.int("eqColorMode", 0)
        eqSensitivity = Self.num("eqSensitivity", 1); glassMaterial = Self.int("glassMaterial", 0)
        glassTint = Self.num("glassTint", 0.3); keepOpen = Self.flag("keepOpen", false)
        lockStage = Self.int("lockStage", 2); lockDim = Self.num("lockDim", 0.6); lockRecordSize = Self.num("lockRecordSize", 160)
        lockTitleOn = Self.flag("lockTitleOn", true); lockNextLineOn = Self.flag("lockNextLineOn", true); lockVerticalTitle = Self.flag("lockVerticalTitle", true); constellationBehind = Self.flag("constellationBehind", false)
        lockControlsOn = Self.flag("lockControlsOn", true); lockSoundsOn = Self.flag("lockSoundsOn", true)
        lockGlass = Self.int("lockGlass", 0); lensBend = Self.num("lensBend", 0.5)
        lyricBackground = Self.int("lyricBackground", 1)
        lyricOffset = Self.num("lyricOffset", 0.35); lyricScatter = Self.num("lyricScatter", 0.3)
        lyricColorMode = Self.int("lyricColorMode", 1)
        lyricR = Self.num("lyricR", 1); lyricG = Self.num("lyricG", 1); lyricB = Self.num("lyricB", 1)
        faceLockOn = Self.flag("faceLockOn", false); fahrenheit = Self.flag("fahrenheit", false)
        showMenuIcon = Self.flag("showMenuIcon", true); browsersOn = Self.flag("browsersOn", true)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func temp(_ c: Int) -> Int { fahrenheit ? Int((Double(c) * 9 / 5 + 32).rounded()) : c }

    func resetGlow() {
        glowOnlyWhilePlaying = true; glowColorMode = 0; glowR = 1; glowG = 0.4; glowB = 0.3; glowEdges = 0
        glowIntensity = 1; glowThickness = 6; glowBlur = 12; glowBPM = 100
    }
}

enum Pane: String, CaseIterable, Identifiable {
    case general = "General", notch = "Notch", playing = "Now Playing"
    case lyrics = "Lyrics", lock = "Lock Screen", desktop = "Desktop", glow = "Beat Glow"
    case privacy = "Privacy and Permissions", about = "About"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: return "gearshape"; case .notch: return "capsule.portrait"; case .playing: return "music.note.list"
        case .lyrics: return "text.quote"; case .lock: return "lock"; case .desktop: return "macwindow"
        case .glow: return "light.max"; case .privacy: return "hand.raised"; case .about: return "info.circle"
        }
    }
}

struct PaneGroup: Identifiable {
    let id: String
    let panes: [Pane]
}

struct SettingsView: View {
    @ObservedObject var s = SettingsStore.shared
    @ObservedObject var face = FaceLock.shared
    @ObservedObject var player: NowPlaying
    var preview: () -> Void
    @State private var pane: Pane = .general
    @State private var tint = Color.accentColor

    private let groups: [PaneGroup] = [
        PaneGroup(id: "Spindle", panes: [.general, .notch, .playing]),
        PaneGroup(id: "Looks", panes: [.lyrics, .lock, .desktop, .glow]),
        PaneGroup(id: "Safety", panes: [.privacy, .about])
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 214)
            Divider().opacity(0.35)
            Form { content(pane) }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
        }
        .frame(width: 840, height: 590)
        .background(background)
        .tint(tint)
        // The window takes its colour from the album that is playing, and moves to the next one with the song.
        .task(id: player.track?.artworkURL) {
            if let c = await AlbumColor.from(player.track?.artworkURL) {
                withAnimation(.easeInOut(duration: 1.2)) { tint = c }
            }
        }
    }

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(colors: [tint.opacity(0.38), tint.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [tint.opacity(0.28), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 520)
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(groups) { g in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(g.id.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 10)
                        ForEach(g.panes) { p in row(p) }
                    }
                }
            }
            .padding(12).padding(.top, 24)
        }
    }

    private func row(_ p: Pane) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { pane = p } } label: {
            Label(p.rawValue, systemImage: p.icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 8).fill(pane == p ? tint.opacity(0.30) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: building blocks

    private func slider(_ title: String, _ v: Binding<Double>, _ r: ClosedRange<Double>, _ f: String = "%.2f") -> some View {
        HStack { Text(title); Slider(value: v, in: r); Text(String(format: f, v.wrappedValue)).monospacedDigit().frame(width: 52, alignment: .trailing) }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }

    private func colourPicker(_ title: String, _ r: Binding<Double>, _ g: Binding<Double>, _ b: Binding<Double>) -> some View {
        ColorPicker(title, selection: Binding<Color>(
            get: { Color(red: r.wrappedValue, green: g.wrappedValue, blue: b.wrappedValue) },
            set: { c in
                let n = NSColor(c).usingColorSpace(.sRGB) ?? .white
                r.wrappedValue = Double(n.redComponent); g.wrappedValue = Double(n.greenComponent); b.wrappedValue = Double(n.blueComponent)
            }))
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

    private func permRow(_ title: String, _ detail: String, _ granted: Bool?, _ pane: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted == true ? "checkmark.circle.fill" : (granted == false ? "xmark.circle" : "questionmark.circle"))
                .foregroundStyle(granted == true ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
            }
        }
    }

    // MARK: the panes

    @ViewBuilder private func content(_ p: Pane) -> some View {
        switch p {
        case .general:
            Section("Show") {
                Toggle("Dynamic island", isOn: $s.islandOn)
                Toggle("Pop-ups (headphones, charging, Focus, alarm)", isOn: $s.toastsOn)
                Toggle("Volume and brightness edge bars", isOn: $s.edgeSlidersOn)
                Toggle("Lock screen lyrics", isOn: $s.lockLyricsOn)
                Toggle("Beat Glow", isOn: $s.glowOn)
                Toggle("Desktop widget", isOn: $s.widgetOn)
                Toggle("Lyrics on the desktop", isOn: $s.desktopLyricsOn)
            }
            Section("Startup and menu bar") {
                Toggle("Open Spindle at login", isOn: $s.launchAtLogin)
                Toggle("Show menu bar icon", isOn: $s.showMenuIcon)
                note("If you hide the icon, open Spindle again from Applications to bring these settings back.")
            }
            Section("Units, sleep and clock") {
                Toggle("Show temperature in °F", isOn: $s.fahrenheit)
                Toggle("Keep the screen awake while media plays", isOn: $s.screenKeeper)
                Picker("Clock font", selection: $s.clockFont) { Text("Rounded").tag(0); Text("Serif").tag(1); Text("Mono").tag(2) }
            }
            Section("Key sounds") {
                Toggle("Play a click on every key press", isOn: $s.keySoundsOn)
                Picker("Set", selection: $s.keySoundSet) { Text("Office").tag(0); Text("Retro").tag(1); Text("Soft").tag(2) }
                slider("Volume", $s.keySoundVolume, 0...1)
                note("Counts keys system-wide, so it needs Accessibility. Nothing you type is recorded.")
            }

        case .notch:
            Section("Shape and behaviour") {
                Picker("Shape", selection: $s.floatingIsland) { Text("Notch (attached to the top)").tag(false); Text("Floating oval").tag(true) }
                Picker("Open with", selection: $s.openOnClick) { Text("Hover").tag(false); Text("Preview, then click").tag(true) }.pickerStyle(.segmented)
                Toggle("Open the wide dashboard straight away", isOn: $s.bigIsland)
                Toggle("Fade out when nothing is playing", isOn: $s.hideWhenIdle)
                Toggle("Keep the island open (it won't close when you move away)", isOn: $s.keepOpen)
            }
            Section("Look") {
                Picker("Background", selection: $s.glassStyle) { Text("Black").tag(false); Text("Glass").tag(true) }.pickerStyle(.segmented)
                if s.glassStyle {
                    Picker("Frost", selection: $s.glassMaterial) { Text("Light").tag(0); Text("Medium").tag(1); Text("Heavy").tag(2); Text("Solid").tag(3) }
                    slider("Darkness", $s.glassTint, 0...0.8)
                }
                Toggle("Turn the playing cover like a record", isOn: $s.turntable)
                slider("Size", $s.islandScale, 0.8...1.3)
                slider("Animation speed", $s.animSpeed, 0.6...2.0)
            }
            Section("Equalizer") {
                Toggle("Show the equalizer in the island", isOn: $s.eqOn)
                Stepper("Bars: \(s.eqBars)", value: $s.eqBars, in: 3...8)
                Picker("Colour", selection: $s.eqColorMode) { Text("White").tag(0); Text("Rainbow").tag(1) }
                note("Moves with the real sound once macOS lets Spindle hear system audio. Until then the bars play a gentle demo pattern.")
            }

        case .playing:
            Section("Players") {
                HStack { Image(systemName: "music.note"); Text("Spotify and Apple Music"); Spacer(); Text("Always on").foregroundStyle(.secondary) }
                Toggle("Safari, Chrome, Brave and Edge (YouTube, Spotify Web, SoundCloud and more)", isOn: $s.browsersOn)
                note("To read a browser tab, turn on Allow JavaScript from Apple Events: in Safari under the Develop menu; in Chrome, Brave and Edge under View, then Developer. macOS asks once to let Spindle control each browser.")
            }
            Section("Playing now") {
                if let t = player.track {
                    LabeledContent("Song", value: t.title)
                    LabeledContent("Artist", value: t.artist)
                    LabeledContent("From", value: t.source)
                } else {
                    note("Nothing is playing.")
                }
            }

        case .lyrics:
            Section("Style") {
                Picker("Lyric style", selection: $s.lyricStyle) {
                    Text("Constellation").tag(0); Text("Big Words").tag(1); Text("Lens").tag(2); Text("Terminal").tag(3); Text("Aura").tag(4)
                }
                note(styleNote(s.lyricStyle))
                Toggle("Constellation network behind the words (Aura and Big Words)", isOn: $s.constellationBehind)
                Toggle("Twinkling star background", isOn: $s.starsOn)
            }
            Section("Colour") {
                Picker("Words take their colour from", selection: $s.lyricColorMode) {
                    Text("White").tag(0); Text("Album cover (bright)").tag(1); Text("Custom").tag(2); Text("Rainbow").tag(3)
                }
                if s.lyricColorMode == 2 { colourPicker("Custom colour", $s.lyricR, $s.lyricG, $s.lyricB) }
            }
            Section("Timing and desktop card") {
                slider("Timing (seconds early)", $s.lyricOffset, -2...2)
                Picker("Behind the words", selection: $s.lyricBackground) { Text("Dark with stars").tag(0); Text("Blurred album cover").tag(1) }
                slider("Scatter (desktop card)", $s.lyricScatter, 0...1)
                note("Lyrics come from LRCLIB when a synced version exists. The lock screen always uses the cover's own colours.")
            }

        case .lock:
            Section("Lock screen") {
                Toggle("Show on the lock screen", isOn: $s.lockLyricsOn)
                Picker("Starts with", selection: $s.lockStage) { Text("Record").tag(0); Text("Cover").tag(1); Text("Lyrics").tag(2) }.pickerStyle(.segmented)
                Toggle("Play, pause and skip in the card", isOn: $s.lockControlsOn)
                Toggle("Click when the Mac locks and unlocks", isOn: $s.lockSoundsOn)
            }
            Section("Look") {
                Toggle("Show the small record in cover and lyrics", isOn: $s.lockRecordOn)
                slider("Record size", $s.lockRecordSize, 100...240, "%.0f")
                slider("Screen darkening", $s.lockDim, 0...1)
                Toggle("Show song title and artist", isOn: $s.lockTitleOn)
                Toggle("Show the next line", isOn: $s.lockNextLineOn)
                Toggle("Song title down the left edge (Constellation)", isOn: $s.lockVerticalTitle)
                Picker("Card", selection: $s.lockGlass) { Text("Liquid, see-through").tag(0); Text("Clear, thinner").tag(1); Text("Off, a solid card").tag(2) }
                slider("Lens bend", $s.lensBend, 0...1)
            }
            Section("Try it") {
                Button("Preview now (10 seconds)", action: preview)
                note("The record turns under the clock. Click it to lift the cover full size, click the cover to fill the lock screen with lyrics, and click the card to cycle back. Play a song first.")
            }

        case .desktop:
            Section("Widget") {
                Toggle("Show the desktop widget", isOn: $s.widgetOn)
                Picker("Style", selection: $s.widgetStyle) { Text("Turntable").tag(0); Text("Record sleeve").tag(1); Text("Aura").tag(2) }
                note("Click the widget to switch style. Drag it to move it.")
                Toggle("Show lyrics on the desktop", isOn: $s.desktopLyricsOn)
            }
            Section("Wallpaper") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                    ForEach(Walls.all) { w in
                        Button { Walls.apply(w) } label: {
                            VStack(spacing: 4) {
                                Image(nsImage: Walls.thumb(w)).resizable().scaledToFill()
                                    .frame(width: 100, height: 62).clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(w.name).font(.caption)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }

        case .glow:
            Section("Beat Glow") {
                Toggle("Enable Beat Glow", isOn: $s.glowOn)
                Toggle("Only while music is playing", isOn: $s.glowOnlyWhilePlaying)
            }
            Section("Colour") {
                Picker("Colour from", selection: $s.glowColorMode) { Text("Album cover").tag(0); Text("Custom").tag(1); Text("Rainbow").tag(2) }
                if s.glowColorMode == 1 { colourPicker("Custom colour", $s.glowR, $s.glowG, $s.glowB) }
            }
            Section("Shape") {
                Picker("Where", selection: $s.glowEdges) { Text("All edges").tag(0); Text("Top").tag(1); Text("Bottom").tag(2); Text("Sides").tag(3) }
                slider("Brightness", $s.glowIntensity, 0.2...1)
                slider("Thickness", $s.glowThickness, 2...24, "%.0f")
                slider("Softness", $s.glowBlur, 4...40, "%.0f")
                slider("Steady pulse (BPM)", $s.glowBPM, 60...180, "%.0f")
                note("The glow follows the music once macOS lets Spindle hear system audio. Until then it pulses at the BPM above.")
                Button("Reset Beat Glow settings") { s.resetGlow() }
            }

        case .privacy:
            Section("Face Unlock for private tabs (beta)") {
                Toggle("Lock Tray, Notes, Tasks and Diary until it's you", isOn: $s.faceLockOn)
                HStack {
                    Button(face.enrolled > 0 ? "Redo Face Unlock" : "Set up Face Unlock") { face.startEnrol() }
                    if face.enrolled > 0 { Button("Remove face data") { face.resetFace() } }
                }
                if !face.status.isEmpty { Text(face.status).font(.caption) }
                slider("Strictness", $face.threshold, 0.2...0.9)
                note("Lower is stricter. A convenience lock, not strong security: a photo of you might fool it. It does not unlock your Mac. Touch ID or your password always works.")
            }
            Section("Permissions") {
                permRow("Audio capture", "Equalizer and Beat Glow follow the music. Asked once, when music first plays.", nil, "Privacy_ScreenCapture")
                permRow("Accessibility", "Typing speed and key sounds.", AXIsProcessTrusted(), "Privacy_Accessibility")
                permRow("Camera", "Mirror and Face Unlock.", AVCaptureDevice.authorizationStatus(for: .video) == .authorized, "Privacy_Camera")
                permRow("Automation", "Spotify, Music, Safari and Chrome.", nil, "Privacy_Automation")
                permRow("Location", "Weather. Without it your approximate city is used.", nil, "Privacy_LocationServices")
                permRow("Full Disk Access", "Focus mode badge.", nil, "Privacy_AllFiles")
                note("Builds from GitHub keep the same signature, so a permission you allow stays allowed. Reopen this window to refresh the ticks.")
            }

        case .about:
            Section("Spindle") {
                Text("Version 0.1.0")
                Text("Weather: MET Norway · Lyrics: LRCLIB").font(.caption)
                note("Spindle is an independent app and isn't affiliated with Spotify, Apple or Google.")
            }
        }
    }
}

enum SettingsWindow {
    private static var win: NSWindow?
    static func show(player: NowPlaying, preview: @escaping () -> Void) {
        if win == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(player: player, preview: preview)))
            w.title = "Spindle Settings"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.center()
            win = w
        }
        NSApp.activate(ignoringOtherApps: true)
        win?.makeKeyAndOrderFront(nil)
    }
}
