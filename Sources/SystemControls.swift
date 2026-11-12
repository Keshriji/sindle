import Foundation
import AppKit
import CoreGraphics

/// Reads and sets system volume and built-in display brightness.
/// Volume uses AppleScript (public). Brightness uses the private DisplayServices framework,
/// which works on Apple silicon but can change between macOS releases (direct distribution only).
final class SystemControls: ObservableObject {
    @Published var volume = 0.5
    @Published var brightness = 0.5
    private let queue = DispatchQueue(label: "spindle.system")
    private var timer: Timer?

    private typealias GetB = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetB = @convention(c) (UInt32, Float) -> Int32
    private let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        queue.async {
            var v: Double?, b: Double?
            var err: NSDictionary?
            if let r = NSAppleScript(source: "output volume of (get volume settings)")?.executeAndReturnError(&err) {
                v = Double(r.int32Value) / 100
            }
            if let lib = self.lib, let p = dlsym(lib, "DisplayServicesGetBrightness") {
                var f: Float = 0
                if unsafeBitCast(p, to: GetB.self)(CGMainDisplayID(), &f) == 0 { b = Double(f) }
            }
            DispatchQueue.main.async {
                if let v { self.volume = v }
                if let b { self.brightness = b }
            }
        }
    }

    func setVolume(_ x: Double) {
        volume = x
        queue.async {
            var err: NSDictionary?
            _ = NSAppleScript(source: "set volume output volume \(Int(x * 100))")?.executeAndReturnError(&err)
        }
    }

    func setBrightness(_ x: Double) {
        brightness = x
        queue.async {
            if let lib = self.lib, let p = dlsym(lib, "DisplayServicesSetBrightness") {
                _ = unsafeBitCast(p, to: SetB.self)(CGMainDisplayID(), Float(x))
            }
        }
    }
}
