import SwiftUI
import AppKit

/// What changed in this build. Needle shows its notes after an update; Spindle opens this once per
/// version and keeps it in the menu bar afterwards.
struct WhatsNewView: View {
    var finish: () -> Void

    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.0"
    }

    private let items: [(symbol: String, title: String, text: String)] = [
        ("heart.fill", "Liked songs",
         "The heart in the island keeps a song in your Diary, newest first."),
        ("speaker.wave.2.fill", "A click at the lock",
         "One click as your Mac locks, a lighter one as it unlocks."),
        ("light.max", "The light keeps going",
         "Beat Glow now sits above the lock art, so it keeps flashing while the Mac is locked."),
        ("hand.tap", "Peek, then open",
         "The island grows a little as your pointer reaches it, and opens when you click."),
        ("sparkles", "Aura, written in stars",
         "The Aura lyric style joins its words with a soft thread and lights them as they are sung."),
        ("hand.draw", "Two fingers to turn the page",
         "Swipe sideways over the open island to step through its pages.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "opticaldisc").font(.system(size: 30)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What's new in Spindle").font(.title2.bold())
                    Text("Version \(version)").font(.callout).foregroundStyle(.secondary)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(items, id: \.title) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.tint)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).font(.system(size: 13, weight: .semibold))
                                Text(item.text).font(.system(size: 12))
                                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            HStack {
                Spacer()
                Button("Continue") { finish() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480, height: 430)
    }
}

enum WhatsNewController {
    private static var win: NSWindow?
    private static let seenKey = "spindle.whatsNewSeen"

    /// Opens the notes, and remembers the version that was read.
    static func show() {
        if win == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: WhatsNewView(finish: {
                markSeen()
                win?.close()
            })))
            w.title = "What's New"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            win = w
        }
        NSApp.activate(ignoringOtherApps: true)
        win?.makeKeyAndOrderFront(nil)
    }

    /// Called at launch: a new version opens the notes by itself, an old one stays quiet.
    static func showIfNew() {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.0"
        guard UserDefaults.standard.string(forKey: seenKey) != version else { return }
        show()
    }

    private static func markSeen() {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.1.0"
        UserDefaults.standard.set(version, forKey: seenKey)
    }
}
