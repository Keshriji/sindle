import Foundation
import AppKit

struct Track: Equatable {
    var title = "", artist = ""
    var artworkURL: URL?
    var position = 0.0, duration = 1.0
    var source = ""            // "Spotify" or "Music"
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
            if self.running("com.spotify.client"), let r = self.run("""
                tell application "Spotify"
                  if player state is playing then
                    return (name of current track) & "||" & (artist of current track) & "||" & (artwork url of current track) & "||" & (player position as text) & "||" & ((duration of current track) / 1000 as text)
                  end if
                end tell
                """) { result = self.parse(r, source: "Spotify") }
            if result == nil, self.running("com.apple.Music"), let r = self.run("""
                tell application "Music"
                  if player state is playing then
                    return (name of current track) & "||" & (artist of current track) & "||" & "" & "||" & (player position as text) & "||" & (duration of current track as text)
                  end if
                end tell
                """) { result = self.parse(r, source: "Music") }
            DispatchQueue.main.async { if self.track != result { self.track = result } }
        }
    }

    private func parse(_ s: String, source: String) -> Track? {
        let p = s.components(separatedBy: "||")
        guard p.count == 5 else { return nil }
        func num(_ x: String) -> Double { Double(x.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        return Track(title: p[0], artist: p[1], artworkURL: URL(string: p[2]),
                     position: num(p[3]), duration: max(num(p[4]), 1), source: source)
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
