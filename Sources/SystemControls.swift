import Foundation
import AppKit
import CoreGraphics
import CoreAudio
import AudioToolbox

/// Volume uses CoreAudio directly (instant, and it hears changes made with the keyboard keys).
/// Brightness uses the private DisplayServices framework (can break on new macOS releases).
final class SystemControls: ObservableObject {
    @Published var volume = 0.5
    @Published var brightness = 0.5
    private let queue = DispatchQueue(label: "spindle.brightness")
    private var timer: Timer?
    private var volQuiet = Date.distantPast      // ignore system echoes briefly after the user drags
    private var briQuiet = Date.distantPast
    private var listenDev = AudioDeviceID(0)

    private typealias GetB = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetB = @convention(c) (UInt32, Float) -> Int32
    private let lib = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    func start() {
        syncVolume(); syncBrightness(); attachVolumeListener()
        var d = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &d, DispatchQueue.main) { [weak self] _, _ in
            self?.attachVolumeListener(); self?.syncVolume()
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
    private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }
    private static func readVolume() -> Float? {
        let dev = outputDevice(); var a = volumeAddress()
        guard AudioObjectHasProperty(dev, &a) else { return nil }
        var v = Float32(0); var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr ? v : nil
    }
    private static func writeVolume(_ x: Float) {
        let dev = outputDevice(); var a = volumeAddress(); var v = Float32(x)
        AudioObjectSetPropertyData(dev, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
    }
    private func attachVolumeListener() {
        let dev = Self.outputDevice()
        guard dev != listenDev else { return }
        listenDev = dev
        var a = Self.volumeAddress()
        AudioObjectAddPropertyListenerBlock(dev, &a, DispatchQueue.main) { [weak self] _, _ in self?.syncVolume() }
    }

    private func syncVolume() {
        guard Date() > volQuiet, let v = Self.readVolume() else { return }
        if abs(Double(v) - volume) > 0.005 { volume = Double(v) }
    }
    func setVolume(_ x: Double) {
        volQuiet = Date().addingTimeInterval(0.5)
        volume = x
        Self.writeVolume(Float(x))
    }

    // MARK: brightness
    private func syncBrightness() {
        queue.async {
            guard let lib = self.lib, let p = dlsym(lib, "DisplayServicesGetBrightness") else { return }
            var f: Float = 0
            guard unsafeBitCast(p, to: GetB.self)(CGMainDisplayID(), &f) == 0 else { return }
            DispatchQueue.main.async {
                if Date() > self.briQuiet, abs(Double(f) - self.brightness) > 0.005 { self.brightness = Double(f) }
            }
        }
    }
    func setBrightness(_ x: Double) {
        briQuiet = Date().addingTimeInterval(0.5)
        brightness = x
        queue.async {
            if let lib = self.lib, let p = dlsym(lib, "DisplayServicesSetBrightness") {
                _ = unsafeBitCast(p, to: SetB.self)(CGMainDisplayID(), Float(x))
            }
        }
    }
}
