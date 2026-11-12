import Foundation
import AppKit
import CoreAudio
import AudioToolbox
import Darwin

/// Reads and sets the system output volume and the built-in display brightness.
///
/// Volume uses CoreAudio (public API, instant, no Automation permission). Not every output device
/// exposes the same control: built-in speakers and most Bluetooth devices have a virtual main
/// volume, while HDMI, external displays and some docks only publish a scalar per output channel.
/// The volume paths below try each in turn so the slider works on all of them, and mute is folded
/// into the same state (a muted device reads as 0, and raising the slider unmutes).
///
/// Brightness uses the private DisplayServices framework; when it is not present
/// `brightnessSupported` is false and the app hides the brightness slider instead of showing one
/// that does nothing.
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

    private static func hasProperty(_ device: AudioObjectID, _ addr: AudioObjectPropertyAddress) -> Bool {
        var address = addr
        return AudioObjectHasProperty(device, &address)
    }

    private static func isSettable(_ device: AudioObjectID, _ addr: AudioObjectPropertyAddress) -> Bool {
        var address = addr
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr else { return false }
        return settable.boolValue
    }

    /// Output channel count, used when a device has no main volume (HDMI, displays, docks).
    private static func outputChannels(_ device: AudioObjectID) -> Int {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                              mScope: kAudioDevicePropertyScopeOutput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        var channels = 0
        for buffer in buffers { channels += Int(buffer.mNumberChannels) }
        return channels
    }

    private static func volumeAddress(selector: AudioObjectPropertySelector,
                                      element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: element)
    }

    /// The controls to read and write, in order of preference:
    /// 1. the virtual main volume (built-in speakers, headphones, most Bluetooth output),
    /// 2. the device's main volume scalar,
    /// 3. one scalar per output channel (HDMI, external displays, some docks).
    private static func volumeTargets(_ device: AudioObjectID) -> [AudioObjectPropertyAddress] {
        let virtualMain = volumeAddress(selector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                        element: kAudioObjectPropertyElementMain)
        if hasProperty(device, virtualMain), isSettable(device, virtualMain) {
            return [virtualMain]
        }

        let main = volumeAddress(selector: kAudioDevicePropertyVolumeScalar,
                                 element: kAudioObjectPropertyElementMain)
        if hasProperty(device, main), isSettable(device, main) {
            return [main]
        }

        let channels = min(outputChannels(device), 8)
        guard channels >= 1 else { return [] }
        var targets: [AudioObjectPropertyAddress] = []
        for index in 1...channels {
            let addr = volumeAddress(selector: kAudioDevicePropertyVolumeScalar,
                                     element: AudioObjectPropertyElement(index))
            if hasProperty(device, addr), isSettable(device, addr) { targets.append(addr) }
        }
        return targets
    }

    private static func muteAddress(_ device: AudioObjectID) -> AudioObjectPropertyAddress? {
        for element in [kAudioObjectPropertyElementMain, 1] {
            let addr = volumeAddress(selector: kAudioDevicePropertyMute,
                                     element: AudioObjectPropertyElement(element))
            if hasProperty(device, addr) { return addr }
        }
        return nil
    }

    private static func isMuted(_ device: AudioObjectID) -> Bool {
        guard let found = muteAddress(device) else { return false }
        var addr = found
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &muted) == noErr else { return false }
        return muted != 0
    }

    private static func setMuted(_ device: AudioObjectID, _ muted: Bool) {
        guard let found = muteAddress(device) else { return }
        var addr = found
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectSetPropertyData(device, &addr, 0, nil, size, &value)
    }

    private static func readVolume() -> Double? {
        guard let device = outputDevice() else { return nil }
        var values: [Double] = []
        for target in volumeTargets(device) {
            var addr = target
            var level: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &level) == noErr {
                values.append(Double(level))
            }
        }
        guard let loudest = values.max() else { return nil }
        return isMuted(device) ? 0 : loudest
    }

    private static func writeVolume(_ x: Double) {
        guard let device = outputDevice() else { return }
        let targets = volumeTargets(device)
        guard !targets.isEmpty else { return }
        let level = min(max(x, 0), 1)
        // A muted device would otherwise stay silent while the slider moves: raise it first.
        if level > 0.001, isMuted(device) { setMuted(device, false) }
        var value = Float32(level)
        let size = UInt32(MemoryLayout<Float32>.size)
        for target in targets {
            var addr = target
            AudioObjectSetPropertyData(device, &addr, 0, nil, size, &value)
        }
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
