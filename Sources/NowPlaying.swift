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
    private var polling = false          // touched on the main thread only

    private static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Spindle", isDirectory: true)
    }()

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        poll()
    }

    private func running(_ id: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }

    /// The player to send controls to when nothing is loaded yet, so the island's play button can
    /// still start playback instead of doing nothing.
    private var targetApp: String? {
        if running("com.spotify.client") { return "Spotify" }
        if running("com.apple.Music") { return "Music" }
        return nil
    }

    /// Never lets two AppleScript reads run at once: a slow player used to make polls stack up,
    /// which showed up as controls and progress lagging further and further behind.
    private func poll() {
        guard !polling else { return }
        polling = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            var result: Track?
            if self.running("com.spotify.client") { result = self.spotify() }
            if result == nil, self.running("com.apple.Music") { result = self.music() }
            if let found = result, found.source == "Music", found.artworkURL == nil {
                var withArt = found
                withArt.artworkURL = self.musicArtwork(key: found.title + "|" + found.artist)
                result = withArt
            }
            let next = result
            DispatchQueue.main.async {
                self.polling = false
                if self.track != next { self.track = next }
            }
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

    // MARK: - Apple Music artwork

    /// Music.app exposes the cover only as raw bytes, so it is written once per track into the
    /// caches folder and handed to SwiftUI as a file URL.
    private func musicArtwork(key: String) -> URL? {
        let url = Self.cacheDir.appendingPathComponent("music-" + Self.keyHash(key) + ".img")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let data = rawArtwork(), data.count > 0, data.count < 6_000_000, Self.looksLikeImage(data) else { return nil }
        try? FileManager.default.createDirectory(at: Self.cacheDir, withIntermediateDirectories: true)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    private func rawArtwork() -> Data? {
        var err: NSDictionary?
        let out = NSAppleScript(source: """
        tell application "Music"
          set t to current track
          if (count of artwork of t) is 0 then return ""
          return data of artwork 1 of t
        end tell
        """)?.executeAndReturnError(&err)
        return out?.data
    }

    /// Guards against writing a non-image payload (a text result or an unsupported cover).
    private static func looksLikeImage(_ d: Data) -> Bool {
        let b = [UInt8](d.prefix(12))
        guard b.count >= 4 else { return false }
        if b[0] == 0xFF, b[1] == 0xD8 { return true }                                    // JPEG
        if b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return true }        // PNG
        if b[0] == 0x47, b[1] == 0x49, b[2] == 0x46 { return true }                      // GIF
        if b[0] == 0x49, b[1] == 0x49, b[2] == 0x2A, b[3] == 0x00 { return true }        // TIFF
        if b[0] == 0x4D, b[1] == 0x4D, b[2] == 0x00, b[3] == 0x2A { return true }        // TIFF
        if b.count >= 12, b[4] == 0x66, b[5] == 0x74, b[6] == 0x79, b[7] == 0x70 { return true } // HEIC
        if b.count >= 12, b[0] == 0x52, b[1] == 0x49, b[2] == 0x46, b[3] == 0x46,
           b[8] == 0x57, b[9] == 0x45, b[10] == 0x42, b[11] == 0x50 { return true }      // WebP
        return false
    }

    private static func keyHash(_ s: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in s.utf8 { h = (h ^ UInt64(byte)) &* 0x1000_0000_01b3 }
        return String(h, radix: 16)
    }

    // MARK: - Controls

    func send(_ command: String) {   // "playpause", "next track", "previous track"
        guard let app = (track?.source.isEmpty == false ? track?.source : nil) ?? targetApp else { return }
        DispatchQueue.global().async { _ = self.run("tell application \"\(app)\" to \(command)") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.poll() }
    }
}
