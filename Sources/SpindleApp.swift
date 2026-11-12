import SwiftUI
import AppKit
import Combine

@main
struct SpindleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        MenuBarExtra("Spindle", systemImage: "opticaldisc") {
            Menu("Island shape") {
                ForEach(IslandShape.allCases) { shape in
                    Button(shape.title) { delegate.look.shape = shape }
                }
            }
            Menu("Island finish") {
                ForEach(IslandFinish.allCases) { finish in
                    Button(finish.title) { delegate.look.finish = finish }
                }
            }
            Divider()
            Button("Show or hide desktop widget") { delegate.toggleWidget() }
            Button("Turn beat glow on or off") { delegate.toggleGlow() }
            Divider()
            Button("Quit Spindle") { NSApp.terminate(nil) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: IslandPanel?
    var widget: DesktopWidgetPanel?
    var glow: GlowPanel?
    var bag = Set<AnyCancellable>()
    var edges: [EdgePanel] = []
    let look = Look()
    let player = NowPlaying(), weather = WeatherStore(), lyrics = LyricsStore()
    let system = SystemControls(), status = StatusStore(), tools = Tools()

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = IslandPanel(player: player, weather: weather, lyrics: lyrics, status: status, tools: tools, look: look)
        panel?.orderFrontRegardless()
        edges = [EdgePanel(side: .left, content: VolumeEdge(system: system))]
        if system.brightnessSupported {
            edges.append(EdgePanel(side: .right, content: BrightnessEdge(system: system)))
        }
        edges.forEach { $0.orderFrontRegardless() }
        widget = DesktopWidgetPanel(player: player)
        widget?.orderFrontRegardless()
        glow = GlowPanel(player: player)
        glow?.orderFrontRegardless()
        player.$track.sink { [tools] t in tools.diary.record(t) }.store(in: &bag)
        tools.clock.onRing = { [status] in status.show(Toast(icon: "alarm.fill", text: "Alarm")) }
        player.start(); weather.start(); system.start(); status.start(); tools.start()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.panel?.reposition(); self?.edges.forEach { $0.reposition() }
        }
    }

    func toggleGlow() {
        guard let g = glow else { return }
        g.isVisible ? g.orderOut(nil) : g.orderFrontRegardless()
    }

    func toggleWidget() {
        guard let w = widget else { return }
        w.isVisible ? w.orderOut(nil) : w.orderFrontRegardless()
    }
}
