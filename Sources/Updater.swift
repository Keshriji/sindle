import SwiftUI
import AppKit

/// Checks the public latest-build release and downloads its DMG. The build is signed and notarised by
/// the same workflow, so opening the downloaded image is enough to install it.
final class Updater: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = Updater()

    @Published var status = ""
    @Published var available: String?
    @Published var downloading = false

    private var task: URLSessionDownloadTask?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    private let api = URL(string: "https://api.github.com/repos/Keshriji/sindle/releases/tags/latest-build")!

    func check() {
        status = "Checking…"
        var req = URLRequest(url: api)
        req.setValue("Spindle/1.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let assets = j["assets"] as? [[String: Any]],
                  let dmg = assets.first(where: { ($0["name"] as? String) == "Spindle.dmg" }),
                  let url = dmg["browser_download_url"] as? String,
                  let remote = URL(string: url) else {
                DispatchQueue.main.async { self.status = "Couldn't check for updates" }
                return
            }
            let when = (j["published_at"] as? String) ?? ""
            DispatchQueue.main.async {
                self.available = remote.absoluteString
                self.status = when.isEmpty ? "A new build is available" : "Build from \(when.prefix(10))"
            }
        }.resume()
    }

    func download() {
        guard let s = available, let url = URL(string: s), !downloading else { return }
        downloading = true
        status = "Downloading…"
        task = session.downloadTask(with: url)
        task?.resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.status = "Downloading \(Int(p * 100))%" }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("Spindle-\(Int(Date().timeIntervalSince1970)).dmg")
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: location, to: dest)
        DispatchQueue.main.async {
            self.downloading = false
            self.status = "Downloaded"
            NSWorkspace.shared.open(dest)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error != nil else { return }
        DispatchQueue.main.async {
            self.downloading = false
            self.status = "Download failed"
        }
    }
}

struct UpdateSheetView: View {
    @ObservedObject var updater = Updater.shared
    var close: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle").font(.system(size: 30)).foregroundStyle(.tint)
            Text("Spindle updates").font(.title3.bold())
            Text(updater.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                Button("Check again") { updater.check() }
                Button("Download") { updater.download() }
                    .disabled(updater.available == nil || updater.downloading)
                Button("Close", action: close)
            }
        }
        .padding(24)
        .frame(width: 380)
        .onAppear { if updater.status.isEmpty { updater.check() } }
    }
}

enum UpdaterController {
    private static var win: NSWindow?

    static func show() {
        if win == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: UpdateSheetView(close: { win?.close() })))
            w.title = "Spindle updates"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            win = w
        }
        NSApp.activate(ignoringOtherApps: true)
        win?.makeKeyAndOrderFront(nil)
    }
}
