import SwiftUI
import AppKit
import Combine

@main
struct SpindleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ObservedObject var s = SettingsStore.shared
    var body: some Scene {
        MenuBarExtra("Spindle", systemImage: "opticaldisc", isInserted: $s.showMenuIcon) {
            Toggle("Dynamic island", isOn: $s.islandOn)
            Menu("Island options") {
                Toggle("Floating oval (instead of notch)", isOn: $s.floatingIsland)
                Toggle("Open on click (instead of hover)", isOn: $s.openOnClick)
                Toggle("Fade out when nothing is playing", isOn: $s.hideWhenIdle)
                Toggle("Glass background", isOn: $s.glassStyle)
                Toggle("Lock private tabs (Face Unlock)", isOn: $s.faceLockOn)
            }
            Toggle("Pop-ups", isOn: $s.toastsOn)
            Toggle("Volume and brightness bars", isOn: $s.edgeSlidersOn)
            Toggle("Desktop widget", isOn: $s.widgetOn)
            Toggle("Lyrics on desktop", isOn: $s.desktopLyricsOn)
            Toggle("Beat Glow", isOn: $s.glowOn)
            Toggle("Lock screen lyrics", isOn: $s.lockLyricsOn)
            Divider()
            Button("Settings…") { delegate.openSettings() }
            Button("Preview lock screen lyrics") { delegate.previewLock() }
            Divider()
            Button("Quit Spindle") { NSApp.terminate(nil) }
        }
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
        edges = [EdgePanel(side: .left, content: VolumeEdge(system: system)),
                 EdgePanel(side: .right, content: BrightnessEdge(system: system))]
        widget = DesktopWidgetPanel(player: player)
        glow = GlowPanel(player: player, audio: audio)
        lyricsWidget = DesktopLyricsPanel(player: player, lyrics: lyrics)
        lockLyrics = LockLyrics(player: player, lyrics: lyrics)
        tools.clock.onRing = { [status] in status.show(Toast(icon: "alarm.fill", text: "Alarm")) }

        player.$track.sink { [tools, lyrics] t in
            tools.diary.record(t)
            if let t { lyrics.load(title: t.title, artist: t.artist) }
        }.store(in: &bag)
        SettingsStore.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.applySettings() }
        }.store(in: &bag)

        player.start(); weather.start(); system.start(); status.start(); tools.start()   // audio starts in applySettings, only if something shows it
        lockLyrics?.start()
        applySettings()
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
        audio.setNeeded(s.glowOn || s.eqOn)      // no system-audio capture when nothing shows it
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openSettings(); return true }
    func openSettings() { SettingsWindow.show(preview: { [weak self] in self?.previewLock() }) }
    func previewLock() { lockLyrics?.show(preview: true) }
}
