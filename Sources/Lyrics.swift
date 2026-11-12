import Foundation

struct LyricLine: Equatable { let t: Double; let s: String }

/// Time-synced lyrics from LRCLIB (https://lrclib.net), no API key needed.
final class LyricsStore: ObservableObject {
    @Published var lines: [LyricLine] = []
    private var loadedKey = ""

    func load(title: String, artist: String) {
        let key = title + "|" + artist
        guard key != loadedKey else { return }
        loadedKey = key
        lines = []
        var comps = URLComponents(string: "https://lrclib.net/api/get")!
        comps.queryItems = [.init(name: "track_name", value: title), .init(name: "artist_name", value: artist)]
        var req = URLRequest(url: comps.url!)
        req.setValue("Spindle/1.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lrc = obj["syncedLyrics"] as? String else { return }
            let parsed = Self.parse(lrc)
            DispatchQueue.main.async { if self.loadedKey == key { self.lines = parsed } }
        }.resume()
    }

    static func parse(_ text: String) -> [LyricLine] {
        var out: [LyricLine] = []
        for raw in text.split(separator: "\n") {
            guard raw.hasPrefix("["), let close = raw.firstIndex(of: "]") else { continue }
            let stamp = raw[raw.index(after: raw.startIndex)..<close].split(separator: ":")
            guard stamp.count == 2, let m = Double(stamp[0]), let s = Double(stamp[1]) else { continue }
            let words = raw[raw.index(after: close)...].trimmingCharacters(in: .whitespaces)
            out.append(LyricLine(t: m * 60 + s, s: words))
        }
        return out
    }

    func index(at position: Double) -> Int? {
        lines.lastIndex { $0.t <= position + 0.3 }
    }
}
