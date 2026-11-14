import SwiftUI
import AppKit

/// A simple supporter licence. Spindle does not gate any feature behind it; this only records a code
/// and shows how long the free period has been running.
final class Licensing: ObservableObject {
    static let shared = Licensing()

    @Published var code: String { didSet { UserDefaults.standard.set(code, forKey: "spindle.code") } }
    @Published var licensed: Bool { didSet { UserDefaults.standard.set(licensed, forKey: "spindle.licensed") } }

    let freeDays = 14
    private let firstRun: Date

    init() {
        let d = UserDefaults.standard
        code = d.string(forKey: "spindle.code") ?? ""
        licensed = d.bool(forKey: "spindle.licensed")
        if let t = d.object(forKey: "spindle.firstRun") as? Date {
            firstRun = t
        } else {
            firstRun = Date()
            d.set(firstRun, forKey: "spindle.firstRun")
        }
    }

    var daysLeft: Int {
        let used = Calendar.current.dateComponents([.day], from: firstRun, to: Date()).day ?? 0
        return max(0, freeDays - used)
    }

    var summary: String {
        licensed ? "Licensed — thank you" : "Free days left: \(daysLeft)"
    }

    func redeem() {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else { return }
        licensed = true
    }
}

struct CodeSheetView: View {
    @ObservedObject var license = Licensing.shared
    var close: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "key.fill").font(.system(size: 30)).foregroundStyle(.tint)
            Text("Spindle is free").font(.title3.bold())
            Text(license.summary).font(.caption).foregroundStyle(.secondary)
            TextField("Code", text: $license.code)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
            HStack {
                Button("Close", action: close)
                Button("Redeem") { license.redeem(); close() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

enum CodeSheetController {
    private static var win: NSWindow?

    static func show() {
        if win == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: CodeSheetView(close: { win?.close() })))
            w.title = "Enter a code"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            win = w
        }
        NSApp.activate(ignoringOtherApps: true)
        win?.makeKeyAndOrderFront(nil)
    }
}
