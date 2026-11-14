import Foundation
import AppKit
import CoreGraphics
import CoreAudio
import AudioToolbox
import Darwin

/// Volume uses CoreAudio directly (instant, and it hears changes made with the keyboard keys).
///
/// Devices do not share one control: built-in speakers and most Bluetooth outputs expose a virtual
/// main volume, while HDMI, external displays and some docks only publish a scalar per output
/// channel. Both are tried, so the left-edge slider works everywhere. Mute is folded in: a muted
/// device reads as 0, and raising the slider unmutes it.
///
/// Brightness uses the private DisplayServices framework (can break on new macOS releases).
final class SystemControls: ObservableObject {
    @Published var volume = 0.5
    @Published var brightness = 0.5
    var onChange: ((String, Double) -> Void)?     // fired when volume or brightness changes from outside the sliders
    private let queue = DispatchQueue(label: "spindle.brightness")
    private var timer: Timer?
    private var volQuiet = Date.distantPast      // ignore system echoes briefly after the user drags
    private var briQuiet = Date.distantPast

    private typealias GetB = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetB = @convention(c) (UInt32, Float) -> Int32
    private let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    var brightnessSupported: Bool { getBrightness != nil && setBrightness != nil }
    private var getBrightness: GetB? {
        guard let lib, let p = dlsym(lib, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(p, to: GetB.self)
    }
    private var setBrightness: SetB? {
        guard let lib, let p = dlsym(lib, "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(p, to: SetB.self)
    }

    func start() {
        syncVolume(); syncBrightness()
        var d = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &d, DispatchQueue.main) { [weak self] _, _ in
            self?.syncVolume()          // AirPods, HDMI or a display was just plugged in or chosen
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.syncBrightness(); self?.syncVolume()
        }
    }

    // MARK: CoreAudio volume

    private static func outputDevice() -> AudioDeviceID {
        var id = AudioDeviceID(0); var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
        return id
    }

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }

    private static func hasProperty(_ dev: AudioDeviceID, _ a: AudioObjectPropertyAddress) -> Bool {
        var addr = a
        return AudioObjectHasProperty(dev, &addr)
    }

    private static func isSettable(_ dev: AudioDeviceID, _ a: AudioObjectPropertyAddress) -> Bool {
        var addr = a
        var ok: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(dev, &addr, &ok) == noErr else { return false }
        return ok.boolValue
    }

    /// Output channel count, used when a device has no main volume (HDMI, external displays, docks).
    private static func outputChannels(_ dev: AudioDeviceID) -> Int {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                           mScope: kAudioDevicePropertyScopeOutput,
                                           mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(dev, &a, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, raw) == noErr else { return 0 }
        let buffers = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        var channels = 0
        for buffer in buffers { channels += Int(buffer.mNumberChannels) }
        return channels
    }

    /// In order of preference: virtual main volume, the main volume scalar, then every output
    /// channel. Only controls the device actually lets us set are used.
    private static func volumeTargets(_ dev: AudioDeviceID) -> [AudioObjectPropertyAddress] {
        let virtual = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyElementMain)
        if hasProperty(dev, virtual), isSettable(dev, virtual) { return [virtual] }

        let main = address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain)
        if hasProperty(dev, main), isSettable(dev, main) { return [main] }

        let channels = min(outputChannels(dev), 8)
        guard channels >= 1 else { return [] }
        var targets: [AudioObjectPropertyAddress] = []
        for index in 1...channels {
            let a = address(kAudioDevicePropertyVolumeScalar, AudioObjectPropertyElement(index))
            if hasProperty(dev, a), isSettable(dev, a) { targets.append(a) }
        }
        return targets
    }

    private static func muteAddress(_ dev: AudioDeviceID) -> AudioObjectPropertyAddress? {
        for element in [kAudioObjectPropertyElementMain, 1] {
            let a = address(kAudioDevicePropertyMute, AudioObjectPropertyElement(element))
            if hasProperty(dev, a) { return a }
        }
        return nil
    }

    private static func isMuted(_ dev: AudioDeviceID) -> Bool {
        guard let found = muteAddress(dev) else { return false }
        var a = found
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &muted) == noErr else { return false }
        return muted != 0
    }

    private static func setMuted(_ dev: AudioDeviceID, _ muted: Bool) {
        guard let found = muteAddress(dev) else { return }
        var a = found
        var value: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private static func readVolume() -> Float? {
        let dev = outputDevice()
        var values: [Float] = []
        for target in volumeTargets(dev) {
            var a = target
            var v = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr { values.append(v) }
        }
        guard let loudest = values.max() else { return nil }
        return isMuted(dev) ? 0 : loudest
    }

    private static func writeVolume(_ x: Float) {
        let dev = outputDevice()
        let targets = volumeTargets(dev)
        guard !targets.isEmpty else { return }
        if x > 0.001, isMuted(dev) { setMuted(dev, false) }
        var v = Float32(min(max(x, 0), 1))
        for target in targets {
            var a = target
            AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        }
    }

    private func syncVolume() {
        // CoreAudio queries talk to coreaudiod, which can be slow enough for a Bluetooth device to
        // stall the main thread, so they run on our own queue and only publish back on main.
        queue.async { [weak self] in
            guard let self else { return }
            guard let v = Self.readVolume() else { return }
            DispatchQueue.main.async {
                guard Date() > self.volQuiet else { return }
                if abs(Double(v) - self.volume) > 0.005 {
                    self.volume = Double(v)
                    let x = Double(v)
                    self.onChange?(x <= 0 ? "speaker.slash.fill" : x < 0.34 ? "speaker.wave.1.fill" : x < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill", x)
                }
            }
        }
    }

    func setVolume(_ x: Double) {
        volQuiet = Date().addingTimeInterval(1.5)
        volume = x
        queue.async { Self.writeVolume(Float(x)) }
    }

    // MARK: brightness

    private func syncBrightness() {
        guard let getBrightness else { return }
        queue.async {
            var f: Float = 0
            guard getBrightness(CGMainDisplayID(), &f) == 0 else { return }
            DispatchQueue.main.async {
                if Date() > self.briQuiet, abs(Double(f) - self.brightness) > 0.005 { self.brightness = Double(f); self.onChange?("sun.max.fill", Double(f)) }
            }
        }
    }

    func setBrightness(_ x: Double) {
        briQuiet = Date().addingTimeInterval(1.5)
        brightness = x
        guard let setBrightness else { return }
        queue.async { _ = setBrightness(CGMainDisplayID(), Float(x)) }
    }
}
