import SwiftUI
import AppKit

struct Wall: Identifiable { let id: Int; let name: String; let hex: [UInt32]; var variant = 0 }

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                  blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

struct SeededRNG: RandomNumberGenerator {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Wallpapers are painted in code from a colour palette and a seed, so they are original and cost no download.
enum Walls {
    static let base: [Wall] = [
        Wall(id: 1, name: "Dusk",   hex: [0x1b1b3a, 0x693668, 0xa74482, 0xf84aa7]),
        Wall(id: 2, name: "Lagoon", hex: [0x06283d, 0x1363df, 0x47b5ff, 0xdff6ff]),
        Wall(id: 3, name: "Ember",  hex: [0x2b0a0a, 0x8c1c13, 0xe4572e, 0xffc15e]),
        Wall(id: 4, name: "Moss",   hex: [0x10240f, 0x2d6a4f, 0x74c69d, 0xd8f3dc]),
        Wall(id: 5, name: "Plum",   hex: [0x1a0b2e, 0x4c2a85, 0x8e6bbf, 0xe0c3fc]),
        Wall(id: 6, name: "Citrus", hex: [0x3a2e00, 0xe09f00, 0xf4d35e, 0x7bb274]),
        Wall(id: 7, name: "Slate",  hex: [0x12181f, 0x2f3e4e, 0x5c7a93, 0xa9c0d1]),
        Wall(id: 8, name: "Rose",   hex: [0x3d0c1c, 0xb5446e, 0xf4a6b8, 0xfff0f3]),
        Wall(id: 9, name: "Tide",   hex: [0x03045e, 0x0077b6, 0x00b4d8, 0x90e0ef]),
        Wall(id: 10, name: "Sand",  hex: [0x3b2f2f, 0xa68a64, 0xdda15e, 0xfefae0]),
        Wall(id: 11, name: "Aurora", hex: [0x050a1f, 0x0b6e4f, 0x5ee6b0, 0x7b5cff]),
        Wall(id: 12, name: "Night", hex: [0x000000, 0x0d1b2a, 0x1b263b, 0x415a77]),
    ]

    /// Each palette in four painted styles: soft blobs, oil dabs, diagonal bands, spotlight.
    static let all: [Wall] = base.flatMap { b in
        [("", 0), (" Oil", 1), (" Bands", 2), (" Spot", 3)].map {
            Wall(id: b.id * 10 + $0.1, name: b.name + $0.0, hex: b.hex, variant: $0.1)
        }
    }

    private static var thumbCache: [Int: NSImage] = [:]
    static func thumb(_ w: Wall) -> NSImage {
        if let t = thumbCache[w.id] { return t }
        let t = render(w, size: CGSize(width: 160, height: 100)); thumbCache[w.id] = t; return t
    }

    static func render(_ w: Wall, size: CGSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors = w.hex.map { NSColor(hex: $0) }
            ctx.setFillColor(colors[0].cgColor); ctx.fill(rect)
            var rng = SeededRNG(s: UInt64(w.id) &* 7919 &+ 17)
            let counts = [16, 70, 14, 6]
            let radii: [(CGFloat, CGFloat)] = [(0.25, 0.6), (0.06, 0.16), (0.2, 0.5), (0.3, 0.7)]
            if w.variant == 2 {
                ctx.saveGState(); ctx.translateBy(x: size.width / 2, y: size.height / 2)
                ctx.rotate(by: .pi / 7); ctx.scaleBy(x: 2.6, y: 0.45); ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
            }
            for i in 0..<counts[w.variant] {
                let c = colors[i % colors.count]
                let p = CGPoint(x: .random(in: 0...size.width, using: &rng), y: .random(in: 0...size.height, using: &rng))
                let r = CGFloat.random(in: radii[w.variant].0...radii[w.variant].1, using: &rng) * max(size.width, size.height)
                let g = CGGradient(colorsSpace: cs,
                                   colors: [c.withAlphaComponent(0.85).cgColor, c.withAlphaComponent(0).cgColor] as CFArray,
                                   locations: [0, 1])!
                ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
            }
            if w.variant == 2 { ctx.restoreGState() }
            if w.variant == 3 {
                let mid = CGPoint(x: size.width / 2, y: size.height / 2)
                let v = CGGradient(colorsSpace: cs, colors: [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.6).cgColor] as CFArray, locations: [0.35, 1])!
                ctx.drawRadialGradient(v, startCenter: mid, startRadius: 0, endCenter: mid, endRadius: max(size.width, size.height) * 0.75, options: [])
            }
            return true
        }
    }

    static func apply(_ w: Wall) {
        DispatchQueue.global(qos: .userInitiated).async {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Spindle", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for (i, screen) in NSScreen.screens.enumerated() {
                let px = CGSize(width: min(screen.frame.width * screen.backingScaleFactor, 3840),
                                height: min(screen.frame.height * screen.backingScaleFactor, 2400))
                let img = render(w, size: px)
                guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { continue }
                let url = dir.appendingPathComponent("wall-\(w.id)-\(i)-\(Int(Date().timeIntervalSince1970)).png")
                try? png.write(to: url)
                DispatchQueue.main.async { try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:]) }
            }
        }
    }
}

struct WallpapersPage: View {
    @State private var picked: Int?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Walls.all) { w in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { picked = w.id }
                        Walls.apply(w)
                    } label: {
                        VStack(spacing: 4) {
                            Image(nsImage: Walls.thumb(w)).resizable().scaledToFill()
                                .frame(width: 96, height: 60).clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(.white, lineWidth: picked == w.id ? 2 : 0))
                                .scaleEffect(picked == w.id ? 1.06 : 1)
                            Text(w.name).font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                        }
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 4)
        }.frame(maxHeight: .infinity)
    }
}
