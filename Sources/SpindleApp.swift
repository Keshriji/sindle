import SwiftUI
import AppKit
import Combine

@main
struct SpindleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject var s = SettingsStore.shared   // so the menu bar icon appears/disappears with the setting
    var body: some Scene {
        MenuBarExtra("Spindle", systemImage: "opticaldisc", isInserted: bind(\.showMenuIcon)) {
            Toggle("Dynamic island", isOn: bind(\.islandOn))
            Menu("Island options") {
                Toggle("Floating oval (instead of notch)", isOn: bind(\.floatingIsland))
                Toggle("Open on click (instead of hover)", isOn: bind(\.openOnClick))
                Toggle("Fade out when nothing is playing", isOn: bind(\.hideWhenIdle))
                Toggle("Glass background", isOn: bind(\.glassStyle))
                Toggle("Lock private tabs (Face Unlock)", isOn: bind(\.faceLockOn))
            }
            Toggle("Pop-ups", isOn: bind(\.toastsOn))
            Toggle("Volume and brightness bars", isOn: bind(\.edgeSlidersOn))
            Toggle("Desktop widget", isOn: bind(\.widgetOn))
            Toggle("Lyrics on desktop", isOn: bind(\.desktopLyricsOn))
            Toggle("Beat Glow", isOn: bind(\.glowOn))
            Toggle("Lock screen lyrics", isOn: bind(\.lockLyricsOn))
            Divider()
            Button("Settings…") { delegate.openSettings() }
            Button("Preview lock screen lyrics") { delegate.previewLock() }
            Divider()
            Button("Quit Spindle") { NSApp.terminate(nil) }
        }
    }

    /// A menu Toggle's binding is written back to the store while the menu is being rebuilt. Because
    /// this App observes the store, that write invalidated the app, rebuilt the menu, and wrote again:
    /// an endless loop that pegged a CPU core. Writing only real changes breaks the cycle.
    private func bind<T: Equatable>(_ kp: ReferenceWritableKeyPath<SettingsStore, T>) -> Binding<T> {
        Binding(get: { SettingsStore.shared[keyPath: kp] },
                set: { new in
                    guard SettingsStore.shared[keyPath: kp] != new else { return }
                    SettingsStore.shared[keyPath: kp] = new
                })
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: IslandPanel?
    var widget: DesktopWidgetPanel?
    var glow: GlowPanel?
    var lyricsWidget: DesktopLyricsPanel?
    var edges: [EdgePanel] = []
    var lockLyrics: LockLyrics?
    var bag = Set<AnyCancellable>()
    let player = NowPlaying(), weather = WeatherStore(), lyrics = LyricsStore()
    let system = SystemControls(), status = StatusStore(), tools = Tools(), audio = AudioLevel()

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = IslandPanel(player: player, weather: weather, lyrics: lyrics, status: status, tools: tools, audio: audio)
        panel?.orderFrontRegardless()          // first thing on screen, before any service starts
        edges = [EdgePanel(side: .left, content: VolumeEdge(system: system)),
                 EdgePanel(side: .right, content: BrightnessEdge(system: system))]
        widget = DesktopWidgetPanel(player: player)
        glow = GlowPanel(player: player, audio: audio)
        lyricsWidget = DesktopLyricsPanel(player: player, lyrics: lyrics)
        lockLyrics = LockLyrics(player: player, lyrics: lyrics)
        tools.clock.onRing = { [status] in status.show(Toast(icon: "alarm.fill", text: "Alarm")) }

        player.$track.sink { [tools, lyrics, audio] t in
            tools.diary.record(t)
            audio.setMusicPlaying(t != nil)
            if let t { lyrics.load(title: t.title, artist: t.artist) }
        }.store(in: &bag)
        SettingsStore.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.applySettings() }
        }.store(in: &bag)

        applySettings()                        // window visibility only; cheap

        // Everything else starts on the next turn of the run loop: AppleScript, CoreAudio, location
        // and the accessibility check all take time, and none of them may hold up the first frame.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            self.player.start(); self.weather.start(); self.system.start(); self.status.start(); self.tools.start()
            self.lockLyrics?.start()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.panel?.reposition(); self?.edges.forEach { $0.reposition() }
        }
    }

    private func set(_ w: NSWindow?, _ on: Bool) {
        guard let w else { return }
        if on { w.orderFrontRegardless() } else { w.orderOut(nil) }
    }
    func applySettings() {
        let s = SettingsStore.shared
        set(panel, s.islandOn); edges.forEach { set($0, s.edgeSlidersOn) }
        set(widget, s.widgetOn); set(glow, s.glowOn); set(lyricsWidget, s.desktopLyricsOn)
        audio.setWanted(s.glowOn || s.eqOn)      // no system-audio capture when nothing shows it
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }
    func openSettings() { SettingsWindow.show(preview: { [weak self] in self?.previewLock() }) }
    func previewLock() { lockLyrics?.show(preview: true) }
}
