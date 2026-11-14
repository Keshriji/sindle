import SwiftUI
import AppKit

/// First-run onboarding. Four short pages, then a flag so it does not open again.
struct WelcomeView: View {
    var finish: () -> Void
    @State private var step = 0

    private let pages: [(icon: String, title: String, body: String)] = [
        ("capsule.portrait", "Your notch, alive",
         "Now playing turns the cover into a spinning record, with a live equalizer on the right."),
        ("text.quote", "Lyrics everywhere",
         "Five lyric styles on the lock screen and the desktop, with the next line always ready."),
        ("light.max", "Glow, mirror, tools",
         "Beat Glow lights the screen edges. The mirror uses the camera. Tray, notes, tasks, calendar and mini apps live in the island."),
        ("slider.horizontal.3", "Make it yours",
         "Shape, glass, colours, motion, clock digits and key sounds are all in Settings.")
    ]

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: pages[step].icon)
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .frame(height: 52)
            Text(pages[step].title).font(.title2.bold())
            Text(pages[step].body)
                .font(.body).multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(height: 64)

            HStack(spacing: 6) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }

            HStack {
                Button("Skip") { finish() }
                Spacer()
                if step > 0 { Button("Back") { withAnimation { step -= 1 } } }
                if step < pages.count - 1 {
                    Button("Next") { withAnimation { step += 1 } }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Get started") { finish() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 520, height: 360)
    }
}

enum WelcomeController {
    private static var win: NSWindow?

    static func show() {
        if win == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: WelcomeView(finish: {
                UserDefaults.standard.set(true, forKey: "spindle.welcomeSeen")
                win?.close()
            })))
            w.title = "Welcome to Spindle"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            win = w
        }
        NSApp.activate(ignoringOtherApps: true)
        win?.makeKeyAndOrderFront(nil)
    }
}
