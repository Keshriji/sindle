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
    @Published var lyricScale: Double   { didSet { put("lyricScale", lyricScale) } }
    @Published var starsOn: Bool        { didSet { put("starsOn", starsOn) } }
    @Published var lockRecordOn: Bool   { didSet { put("lockRecordOn", lockRecordOn) } }
    @Published var widgetStyle: Int     { didSet { put("widgetStyle", widgetStyle) } }
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
    @Published var lockControlsOn: Bool { didSet { put("lockControlsOn", lockControlsOn) } }
    @Published var lyricBackground: Int { didSet { put("lyricBackground", lyricBackground) } } // 0 dark, 1 album blur
    @Published var lyricScatter: Double { didSet { put("lyricScatter", lyricScatter) } }
    @Published var lyricOffset: Double  { didSet { put("lyricOffset", lyricOffset) } }       // seconds the lyrics run early
    @Published var lyricLean: Double    { didSet { put("lyricLean", lyricLean) } }
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
    @Published var glowSensitivity: Double { didSet { put("glowSensitivity", glowSensitivity) } }
    @Published var glowDecay: Double    { didSet { put("glowDecay", glowDecay) } }
    @Published var glowBPM: Double      { didSet { put("glowBPM", glowBPM) } }
    // Other
    @Published var faceLockOn: Bool     { didSet { put("faceLockOn", faceLockOn) } }
    @Published var fahrenheit: Bool     { didSet { put("fahrenheit", fahrenheit) } }
    @Published var showMenuIcon: Bool   { didSet { put("showMenuIcon", showMenuIcon) } }
    @Published var launchAtLogin: Bool  {
        didSet { if launchAtLogin { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() } }
    }

    private init() {
        islandOn = Self.flag("islandOn", true); toastsOn = Self.flag("toastsOn", true)
        edgeSlidersOn = Self.flag("edgeSlidersOn", true); widgetOn = Self.flag("widgetOn", true)
        desktopLyricsOn = Self.flag("desktopLyricsOn", false); glowOn = Self.flag("glowOn", true)
        lockLyricsOn = Self.flag("lockLyricsOn", true)
        floatingIsland = Self.flag("floatingIsland", false); openOnClick = Self.flag("openOnClick", false)
        hideWhenIdle = Self.flag("hideWhenIdle", false); glassStyle = Self.flag("glassStyle", false)
        islandScale = Self.num("islandScale", 1); animSpeed = Self.num("animSpeed", 1)
        lyricStyle = Self.int("lyricStyle", 0); lyricScale = Self.num("lyricScale", 1)
        starsOn = Self.flag("starsOn", true); lockRecordOn = Self.flag("lockRecordOn", true)
        widgetStyle = Self.int("widgetStyle", 0)
        glowOnlyWhilePlaying = Self.flag("glowOnlyWhilePlaying", true); glowColorMode = Self.int("glowColorMode", 0)
        glowR = Self.num("glowR", 1); glowG = Self.num("glowG", 0.4); glowB = Self.num("glowB", 0.3)
        glowEdges = Self.int("glowEdges", 0); glowIntensity = Self.num("glowIntensity", 1)
        glowThickness = Self.num("glowThickness", 6); glowBlur = Self.num("glowBlur", 12)
        glowSensitivity = Self.num("glowSensitivity", 6); glowDecay = Self.num("glowDecay", 0.85)
        glowBPM = Self.num("glowBPM", 100)
        eqOn = Self.flag("eqOn", true); eqBars = Self.int("eqBars", 5); eqColorMode = Self.int("eqColorMode", 0)
        eqSensitivity = Self.num("eqSensitivity", 1); glassMaterial = Self.int("glassMaterial", 0)
        glassTint = Self.num("glassTint", 0.3); keepOpen = Self.flag("keepOpen", false)
        lockStage = Self.int("lockStage", 2); lockDim = Self.num("lockDim", 0.6); lockRecordSize = Self.num("lockRecordSize", 160)
        lockTitleOn = Self.flag("lockTitleOn", true); lockNextLineOn = Self.flag("lockNextLineOn", true)
        lockControlsOn = Self.flag("lockControlsOn", true); lyricBackground = Self.int("lyricBackground", 0)
        lyricOffset = Self.num("lyricOffset", 0.35); lyricScatter = Self.num("lyricScatter", 0.3); lyricLean = Self.num("lyricLean", 0)
        lyricColorMode = Self.int("lyricColorMode", 0)
        lyricR = Self.num("lyricR", 1); lyricG = Self.num("lyricG", 1); lyricB = Self.num("lyricB", 1)
        faceLockOn = Self.flag("faceLockOn", false); fahrenheit = Self.flag("fahrenheit", false)
        showMenuIcon = Self.flag("showMenuIcon", true)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func temp(_ c: Int) -> Int { fahrenheit ? Int((Double(c) * 9 / 5 + 32).rounded()) : c }

    func resetGlow() {
        glowOnlyWhilePlaying = true; glowColorMode = 0; glowR = 1; glowG = 0.4; glowB = 0.3; glowEdges = 0
        glowIntensity = 1; glowThickness = 6; glowBlur = 12; glowSensitivity = 6; glowDecay = 0.85; glowBPM = 100
    }
}

enum Pane: String, CaseIterable, Identifiable {
    case general = "General", island = "Island", lyrics = "Lyrics", lock = "Lock Screen", desktop = "Desktop"
    case glow = "Beat Glow", equalizer = "Equalizer", wallpapers = "Wallpapers", privacy = "Privacy", about = "About"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: return "gearshape"; case .island: return "capsule.portrait"; case .lyrics: return "text.quote"
        case .lock: return "lock"; case .desktop: return "macwindow"; case .glow: return "light.max"; case .equalizer: return "waveform"
        case .wallpapers: return "photo"; case .privacy: return "faceid"; case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var s = SettingsStore.shared
    @ObservedObject var face = FaceLock.shared
    var preview: () -> Void
    @State private var pane: Pane? = .general

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { p in Label(p.rawValue, systemImage: p.icon).tag(p) }
                .navigationSplitViewColumnWidth(min: 170, ideal: 180)
        } detail: {
            Form { content(pane ?? .general) }.formStyle(.grouped).navigationTitle((pane ?? .general).rawValue)
        }
        .frame(width: 780, height: 560)
    }

    private func slider(_ title: String, _ v: Binding<Double>, _ r: ClosedRange<Double>, _ f: String = "%.2f") -> some View {
        HStack { Text(title); Slider(value: v, in: r); Text(String(format: f, v.wrappedValue)).monospacedDigit().frame(width: 52, alignment: .trailing) }
    }

    private func permRow(_ title: String, _ granted: Bool?, _ pane: String) -> some View {
        HStack {
            Image(systemName: granted == true ? "checkmark.circle.fill" : (granted == false ? "xmark.circle" : "questionmark.circle"))
                .foregroundStyle(granted == true ? Color.green : Color.secondary)
            Text(title)
            Spacer()
            Button("Open") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
            }
        }
    }

    @ViewBuilder private func content(_ p: Pane) -> some View {
        switch p {
        case .general:
            Section("Show") {
                Toggle("Dynamic island", isOn: $s.islandOn)
                Toggle("Pop-ups (headphones, charging, Focus, alarm)", isOn: $s.toastsOn)
                Toggle("Volume and brightness edge bars", isOn: $s.edgeSlidersOn)
                Toggle("Desktop widget", isOn: $s.widgetOn)
                Toggle("Lyrics on the desktop", isOn: $s.desktopLyricsOn)
                Toggle("Beat Glow", isOn: $s.glowOn)
                Toggle("Lock screen lyrics", isOn: $s.lockLyricsOn)
            }
            Section("Startup and menu bar") {
                Toggle("Open Spindle at login", isOn: $s.launchAtLogin)
                Toggle("Show menu bar icon", isOn: $s.showMenuIcon)
                Text("If you hide the icon, open Spindle again from Applications to bring these settings back.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Units") { Toggle("Show temperature in °F", isOn: $s.fahrenheit) }
            Section("Permissions") {
                permRow("Screen Recording: equalizer and Beat Glow follow the music", CGPreflightScreenCaptureAccess(), "Privacy_ScreenCapture")
                permRow("Accessibility: typing speed", AXIsProcessTrusted(), "Privacy_Accessibility")
                permRow("Camera: mirror and Face Unlock", AVCaptureDevice.authorizationStatus(for: .video) == .authorized, "Privacy_Camera")
                permRow("Location: weather (otherwise your approximate city is used)", nil, "Privacy_LocationServices")
                permRow("Automation: Spotify and Music", nil, "Privacy_Automation")
                permRow("Full Disk Access: Focus mode badge", nil, "Privacy_AllFiles")
                Text("Each is asked for once. Builds from GitHub keep the same signature, so a permission you allow stays allowed. After allowing Screen Recording, reopen Spindle. Reopen this window to refresh the ticks.")
                    .font(.caption).foregroundStyle(.secondary)
            }

        case .island:
            Section("Shape and behaviour") {
                Picker("Shape", selection: $s.floatingIsland) { Text("Notch (attached to the top)").tag(false); Text("Floating oval").tag(true) }
                Picker("Open with", selection: $s.openOnClick) { Text("Hover").tag(false); Text("Preview, then click").tag(true) }.pickerStyle(.segmented)
                Toggle("Fade out when nothing is playing", isOn: $s.hideWhenIdle)
            }
            Section("Look") {
                Picker("Background", selection: $s.glassStyle) { Text("Black").tag(false); Text("Glass").tag(true) }.pickerStyle(.segmented)
                slider("Size", $s.islandScale, 0.8...1.3)
                slider("Animation speed", $s.animSpeed, 0.6...2.0)
            }

            Section("Glass look") {
                Picker("Frost", selection: $s.glassMaterial) { Text("Light").tag(0); Text("Medium").tag(1); Text("Heavy").tag(2); Text("Solid").tag(3) }
                slider("Darkness", $s.glassTint, 0...0.8)
                Text("Applies when Background is set to Glass.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Lock the island") {
                Toggle("Keep the island open (it won't close when you move away)", isOn: $s.keepOpen)
            }

        case .lyrics:
            Section("Style") {
                Picker("Lyric style", selection: $s.lyricStyle) {
                    Text("Stars").tag(0); Text("Big Words").tag(1); Text("Lens").tag(2); Text("Terminal").tag(3); Text("Aura").tag(4)
                }
                slider("Text size", $s.lyricScale, 0.6...1.4)
                slider("Timing (seconds early)", $s.lyricOffset, -2...2)
                Toggle("Twinkling star background", isOn: $s.starsOn)
            }
            Section { Text("Applies to the lock screen and the desktop lyrics card. Lyrics come from LRCLIB when a synced version exists.").font(.caption).foregroundStyle(.secondary) }

            Section("Background") {
                Picker("Behind the words", selection: $s.lyricBackground) { Text("Dark with stars").tag(0); Text("Blurred album cover").tag(1) }
            }
            Section("Colour") {
                Picker("Words take their colour from", selection: $s.lyricColorMode) { Text("White").tag(0); Text("Album cover").tag(1); Text("Custom").tag(2) }
                if s.lyricColorMode == 2 {
                    ColorPicker("Custom colour", selection: Binding<Color>(
                        get: { Color(red: s.lyricR, green: s.lyricG, blue: s.lyricB) },
                        set: { c in
                            let n = NSColor(c).usingColorSpace(.sRGB) ?? .white
                            s.lyricR = Double(n.redComponent); s.lyricG = Double(n.greenComponent); s.lyricB = Double(n.blueComponent)
                        }))
                }
            }
            Section("Motion") {
                slider("Scatter (Big Words)", $s.lyricScatter, 0...1)
                slider("Lean", $s.lyricLean, -12...12, "%.0f°")
            }

        case .lock:
            Section("Lock screen") {
                Toggle("Show on the lock screen", isOn: $s.lockLyricsOn)
                Picker("Starts with", selection: $s.lockStage) { Text("Record").tag(0); Text("Cover").tag(1); Text("Lyrics").tag(2) }.pickerStyle(.segmented)
                Toggle("Play, pause and skip bar (also switches Record → Cover → Lyrics)", isOn: $s.lockControlsOn)
            }
            Section("Look") {
                Toggle("Spinning record (with lyrics)", isOn: $s.lockRecordOn)
                slider("Record size", $s.lockRecordSize, 100...240, "%.0f")
                slider("Screen darkening", $s.lockDim, 0...1)
                Toggle("Show song title and artist", isOn: $s.lockTitleOn)
                Toggle("Show the next line", isOn: $s.lockNextLineOn)
            }
            Section {
                Button("Preview now (10 seconds)", action: preview)
                Text("Uses private macOS features, so it may not appear on every macOS version. The preview shows it on your desktop.").font(.caption).foregroundStyle(.secondary)
            }

        case .desktop:
            Section("Widget") {
                Toggle("Show the desktop widget", isOn: $s.widgetOn)
                Picker("Style", selection: $s.widgetStyle) { Text("Turntable").tag(0); Text("Record sleeve").tag(1); Text("Aura").tag(2) }
                Text("Click the widget to switch style. Drag it to move it.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Lyrics card") { Toggle("Show lyrics on the desktop", isOn: $s.desktopLyricsOn) }

        case .glow:
            Section("Beat Glow") {
                Toggle("Enable Beat Glow", isOn: $s.glowOn)
                Toggle("Only while music is playing", isOn: $s.glowOnlyWhilePlaying)
            }
            Section("Colour") {
                Picker("Colour from", selection: $s.glowColorMode) { Text("Album cover").tag(0); Text("Custom").tag(1); Text("Rainbow").tag(2) }
                if s.glowColorMode == 1 {
                    ColorPicker("Custom colour", selection: Binding<Color>(
                        get: { Color(red: s.glowR, green: s.glowG, blue: s.glowB) },
                        set: { c in
                            let n = NSColor(c).usingColorSpace(.sRGB) ?? .white
                            s.glowR = Double(n.redComponent); s.glowG = Double(n.greenComponent); s.glowB = Double(n.blueComponent)
                        }))
                }
            }
            Section("Shape") {
                Picker("Where", selection: $s.glowEdges) { Text("All edges").tag(0); Text("Top").tag(1); Text("Bottom").tag(2); Text("Sides").tag(3) }
                slider("Brightness", $s.glowIntensity, 0.2...1)
                slider("Thickness", $s.glowThickness, 2...24, "%.0f")
                slider("Softness", $s.glowBlur, 4...40, "%.0f")
            }
            Section("Reaction") {
                slider("Sensitivity", $s.glowSensitivity, 1...14, "%.1f")
                slider("Fade speed", $s.glowDecay, 0.5...0.97)
                slider("Steady pulse (BPM)", $s.glowBPM, 60...180, "%.0f")
                Text("Sensitivity and fade speed apply when Spindle can hear system audio (macOS asks for Screen Recording permission). Without it, the glow pulses at the BPM above.").font(.caption).foregroundStyle(.secondary)
            }
            Section { Button("Reset Beat Glow settings") { s.resetGlow() } }

        case .equalizer:
            Section("Equalizer") {
                Toggle("Show the equalizer in the island", isOn: $s.eqOn)
                Stepper("Bars: \(s.eqBars)", value: $s.eqBars, in: 3...8)
                Picker("Colour", selection: $s.eqColorMode) { Text("White").tag(0); Text("Rainbow").tag(1) }
                slider("Sensitivity", $s.eqSensitivity, 0.3...3)
                Text("Moves with the real sound when Spindle can hear system audio (Screen Recording permission). Without it, the bars play a gentle demo pattern.").font(.caption).foregroundStyle(.secondary)
            }

        case .wallpapers:
            Section("Desktop wallpaper") {
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

        case .privacy:
            Section("Private tabs (Tray, Notes, Tasks, Diary)") {
                Toggle("Lock them until it's you", isOn: $s.faceLockOn)
                HStack {
                    Button(face.enrolled > 0 ? "Redo Face Unlock (beta)" : "Set up Face Unlock (beta)") { face.startEnrol() }
                    if face.enrolled > 0 { Button("Remove face data") { face.resetFace() } }
                }
                if !face.status.isEmpty { Text(face.status).font(.caption) }
                slider("Strictness", $face.threshold, 0.2...0.9)
                Text("Lower is stricter. A convenience lock, not strong security: a photo of you might fool it. It does not unlock your Mac. Touch ID or your password always works.").font(.caption).foregroundStyle(.secondary)
            }

        case .about:
            Section("Spindle") {
                Text("Version 0.1.0")
                Text("Weather: MET Norway · Lyrics: LRCLIB").font(.caption)
                Text("Spindle is an independent app and isn't affiliated with Spotify or Apple.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

enum SettingsWindow {
    private static var win: NSWindow?
    static func show(preview: @escaping () -> Void) {
        if win == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(preview: preview)))
            w.title = "Spindle Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            win = w
        }
        NSApp.activate(ignoringOtherApps: true)
        win?.makeKeyAndOrderFront(nil)
    }
}
