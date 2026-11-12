import Foundation
import AppKit

struct Track: Equatable {
    var title = "", artist = ""
    var artworkURL: URL?
    var position = 0.0, duration = 1.0
    var source = ""            // "Spotify" or "Music"
    var isPlaying = false      // a paused track is still reported, so the island can resume it
}

/// Reads the current track from Spotify or Apple Music via AppleScript.
/// First run: macOS asks permission (Automation). Needs NSAppleEventsUsageDescription.
final class NowPlaying: ObservableObject {
    @Published var track: Track?
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    private func running(_ id: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    private func poll() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            var result: Track?
            if self.running("com.spotify.client") { result = self.spotify() }
            if result == nil, self.running("com.apple.Music") { result = self.music() }
            let next = result
            DispatchQueue.main.async { if self.track != next { self.track = next } }
        }
    }

    private func spotify() -> Track? {
        let r = run("""
        tell application "Spotify"
          if player state is stopped then return ""
          set t to current track
          return (name of t) & "||" & (artist of t) & "||" & (artwork url of t) & "||" & (player position as text) & "||" & ((duration of t) / 1000 as text) & "||" & (player state as text)
        end tell
        """)
        return r.flatMap { parse($0, source: "Spotify") }
    }

    private func music() -> Track? {
        let r = run("""
        tell application "Music"
          if player state is stopped then return ""
          set t to current track
          return (name of t) & "||" & (artist of t) & "||" & "||" & (player position as text) & "||" & (duration of t as text) & "||" & (player state as text)
        end tell
        """)
        return r.flatMap { parse($0, source: "Music") }
    }

    private func parse(_ s: String, source: String) -> Track? {
        let p = s.components(separatedBy: "||")
        guard p.count >= 6, !p[0].isEmpty else { return nil }
        func num(_ x: String) -> Double { Double(x.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        return Track(title: p[0], artist: p[1], artworkURL: URL(string: p[2]),
                     position: max(num(p[3]), 0), duration: max(num(p[4]), 1),
                     source: source, isPlaying: p[5].contains("playing"))
    }

    private func run(_ src: String) -> String? {
        var err: NSDictionary?
        let out = NSAppleScript(source: src)?.executeAndReturnError(&err)
        return out?.stringValue
    }

    func send(_ command: String) {   // "playpause", "next track", "previous track"
        guard let app = track?.source else { return }
        DispatchQueue.global().async { _ = self.run("tell application \"\(app)\" to \(command)") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.poll() }
    }
}
