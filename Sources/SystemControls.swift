import Foundation
import AppKit
import CoreAudio
import AudioToolbox
import Darwin

/// Reads and sets the system output volume and the built-in display brightness.
/// Volume uses CoreAudio: public API, instant, no Automation permission, and it needs no polling
/// round trip through AppleScript. Brightness uses the private DisplayServices framework; when it
/// is not present `brightnessSupported` is false and the app hides the brightness slider instead of
/// showing one that does nothing.
final class SystemControls: ObservableObject {
    @Published var volume = 0.5
    @Published var brightness = 0.5

    private typealias GetB = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetB = @convention(c) (UInt32, Float) -> Int32

    private let getBrightness: GetB?
    private let setBrightness: SetB?
    private let queue = DispatchQueue(label: "spindle.system")
    private var timer: Timer?

    private var pendingVolume: Double?      // touched on `queue` only
    private var writingVolume = false       // touched on `queue` only
    private var lastEdit = Date.distantPast // touched on the main thread only

    var brightnessSupported: Bool { getBrightness != nil && setBrightness != nil }

    init() {
        let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        func symbol(_ name: String) -> UnsafeMutableRawPointer? {
            guard let lib else { return nil }
            return dlsym(lib, name)
        }
        getBrightness = symbol("DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetB.self) }
        setBrightness = symbol("DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetB.self) }
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
    }

    /// Pulls the real system values. Skipped for a moment after the user changes something so a
    /// stale read cannot snap the slider back under their finger.
    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let v = Self.readVolume()
            let b = self.readBrightness()
            DispatchQueue.main.async {
                guard Date().timeIntervalSince(self.lastEdit) > 1.2 else { return }
                if let v, abs(v - self.volume) > 0.01 { self.volume = v }
                if let b, abs(b - self.brightness) > 0.01 { self.brightness = b }
            }
        }
    }

    // MARK: - Volume

    /// Coalesces a burst of drag events into the latest value, so dragging cannot queue up dozens
    /// of writes (which is what made the slider feel laggy and keep moving after release).
    func setVolume(_ x: Double) {
        let v = min(max(x, 0), 1)
        volume = v
        lastEdit = Date()
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingVolume = v
            guard !self.writingVolume else { return }
            self.writingVolume = true
            while let target = self.pendingVolume {
                self.pendingVolume = nil
                Self.writeVolume(target)
            }
            self.writingVolume = false
        }
    }

    private static func outputDevice() -> AudioObjectID? {
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device)
        return status == noErr && device != 0 ? device : nil
    }

    private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                   mScope: kAudioObjectPropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func readVolume() -> Double? {
        guard let device = outputDevice() else { return nil }
        var addr = volumeAddress()
        var level: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &level) == noErr else { return nil }
        return Double(level)
    }

    private static func writeVolume(_ x: Double) {
        guard let device = outputDevice() else { return }
        var addr = volumeAddress()
        var level = Float32(min(max(x, 0), 1))
        let size = UInt32(MemoryLayout<Float32>.size)
        AudioObjectSetPropertyData(device, &addr, 0, nil, size, &level)
    }

    // MARK: - Brightness

    func setBrightness(_ x: Double) {
        let v = min(max(x, 0), 1)
        brightness = v
        lastEdit = Date()
        guard let setBrightness else { return }
        queue.async { _ = setBrightness(CGMainDisplayID(), Float(v)) }
    }

    private func readBrightness() -> Double? {
        guard let getBrightness else { return nil }
        var level: Float = 0
        guard getBrightness(CGMainDisplayID(), &level) == 0 else { return nil }
        return Double(level)
    }
}
