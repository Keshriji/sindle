import Foundation
import CoreAudio
import AudioToolbox
import Accelerate
import SwiftUI

/// Listens to the Mac's system audio and reports the beat of what is playing.
///
/// This uses a Core Audio "tap" (macOS 14.2 and later). The permission it needs is *Audio Capture*, asked once,
/// not Screen Recording. Screen Recording is the one macOS keeps re-asking about (and re-confirms every month),
/// which is why the old version seemed to ask again after you had allowed it. Nothing is recorded or sent anywhere.
///
/// Audio arrives in small buffers; the last 1024 samples are analysed 20 times a second, and the results are
/// published in a single assignment so SwiftUI is not flooded.
final class AudioLevel: NSObject, ObservableObject {
    /// 0...1 beat envelope: jumps to 1 on a detected beat and fades over about half a second.
    @Published var level = 0.0
    var lastSample = Date.distantPast         // read by the glow to know if live audio is arriving
    @Published var bands = [Double](repeating: 0, count: 8)
    /// True while the tap hears only silence although music is playing: audio access has not been allowed.
    @Published var needsPermission = false

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let ioQueue = DispatchQueue(label: "spindle.audio.tap", qos: .userInitiated)
    private var running = false
    private var starting = false
    private var listening = false
    private var wanted = false
    private var hasMusic = false
    private var lastPublish = Date.distantPast
    private var silentSince: Date?
    private var ring: [Float] = []             // touched on ioQueue only
    private var energy: [Double] = []          // recent low-band energy, used to find beats
    private var lastBeat = Date.distantPast
    private lazy var fftSetup = vDSP_create_fftsetup(10, FFTRadix(kFFTRadix2))

    func start() {
        guard !running, !starting else { return }
        guard #available(macOS 14.2, *) else { return }
        starting = true
        listenForOutputChanges()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let ok = self.startTap()
            DispatchQueue.main.async {
                self.starting = false
                self.running = ok
                if !ok { self.needsPermission = true }
            }
        }
    }

    /// Capture runs only when something shows it (Beat Glow or an equalizer) *and* music is playing.
    func setWanted(_ on: Bool) {
        wanted = on
        refreshState()
    }

    func setMusicPlaying(_ on: Bool) {
        hasMusic = on
        refreshState()
    }

    private func refreshState() {
        if wanted && hasMusic { start() } else if !wanted { stop() }
    }

    func stop() {
        guard running || starting else { return }
        running = false
        let agg = aggregateID, tap = tapID, proc = procID
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        procID = nil
        DispatchQueue.global(qos: .utility).async {
            if let proc { AudioDeviceStop(agg, proc); AudioDeviceDestroyIOProcID(agg, proc) }
            if agg != AudioObjectID(kAudioObjectUnknown) { AudioHardwareDestroyAggregateDevice(agg) }
            if #available(macOS 14.2, *), tap != AudioObjectID(kAudioObjectUnknown) { AudioHardwareDestroyProcessTap(tap) }
        }
    }

    // MARK: the tap

    @available(macOS 14.2, *)
    private func startTap() -> Bool {
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.name = "Spindle"
        desc.uuid = UUID()
        desc.isPrivate = true
        desc.muteBehavior = .unmuted                      // the music keeps playing normally

        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(desc, &tap) == noErr else { return false }
        guard let outputUID = Self.defaultOutputUID() else {
            AudioHardwareDestroyProcessTap(tap)
            return false
        }
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Spindle Audio Tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: desc.uuid.uuidString]]
        ]
        var agg = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(description as CFDictionary, &agg) == noErr else {
            AudioHardwareDestroyProcessTap(tap)
            return false
        }
        var proc: AudioDeviceIOProcID?
        let made = AudioDeviceCreateIOProcIDWithBlock(&proc, agg, ioQueue) { [weak self] _, input, _, _, _ in
            self?.handle(input)
        }
        guard made == noErr, let proc, AudioDeviceStart(agg, proc) == noErr else {
            AudioHardwareDestroyAggregateDevice(agg)
            AudioHardwareDestroyProcessTap(tap)
            return false
        }
        tapID = tap
        aggregateID = agg
        procID = proc
        return true
    }

    private static func defaultOutputUID() -> String? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return nil }
        var uid: Unmanaged<CFString>?
        var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var uidAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID,
                                                    mScope: kAudioObjectPropertyScopeGlobal,
                                                    mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &uidAddress, 0, nil, &uidSize, &uid) == noErr, let value = uid else { return nil }
        return value.takeRetainedValue() as String
    }

    /// The tap is tied to the output device that was current when it was made, so plugging in headphones means
    /// building it again.
    private func listenForOutputChanges() {
        guard !listening else { return }
        listening = true
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main) { [weak self] _, _ in
            guard let self, self.running else { return }
            self.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.refreshState() }
        }
    }

    // MARK: analysis (runs on the audio queue)

    private func handle(_ list: UnsafePointer<AudioBufferList>) {
        let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
        guard let first = abl.first, let raw = first.mData else { return }
        let channels = max(Int(first.mNumberChannels), 1)
        let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * channels)
        guard frames > 0 else { return }
        let p = raw.assumingMemoryBound(to: Float.self)
        var peak: Float = 0
        for i in 0..<frames {
            let sample = p[i * channels]                   // left channel is enough for a beat
            ring.append(sample)
            peak = max(peak, abs(sample))
        }
        if ring.count > 4096 { ring.removeFirst(ring.count - 2048) }

        let now = Date()
        if peak > 0.0001 { silentSince = nil } else if silentSince == nil { silentSince = now }
        guard now.timeIntervalSince(lastPublish) >= 0.05, ring.count >= 1024 else { return }
        lastPublish = now
        let tail = Array(ring.suffix(1024))
        let bandVals: [Float] = tail.withUnsafeBufferPointer { spectrum($0.baseAddress!, 1024) }
        let silent = silentSince
        DispatchQueue.main.async { self.publish(bandVals, silentSince: silent) }
    }

    private func publish(_ bandSample: [Float], silentSince: Date?) {
        let set = SettingsStore.shared
        let now = Date()
        let silentFor: Double = silentSince.map { now.timeIntervalSince($0) } ?? 0
        if silentFor < 1 { lastSample = now }                          // real sound: the bars may follow it
        if silentFor > 8, hasMusic {
            if !needsPermission { needsPermission = true }             // music is playing but nothing is heard
        } else if silentSince == nil, needsPermission {
            needsPermission = false
        }
        guard bandSample.count == 8 else { return }
        var next = bands
        for b in 0..<8 {
            let v = min(1, Double(bandSample[b]) * set.eqSensitivity)
            next[b] = v > next[b] ? v : next[b] * 0.82 + v * 0.18
        }
        bands = next                                                   // one change notification, not eight

        // Beat: the bass rising above its own recent average. That puts the glow on the kick drum.
        let low = Double(bandSample[0])
        energy.append(low)
        if energy.count > 43 { energy.removeFirst() }                  // about 2 s of history
        let avg = energy.reduce(0, +) / Double(energy.count)
        if low > max(avg * 1.4, 0.15), now.timeIntervalSince(lastBeat) > 0.22 {
            lastBeat = now
            level = 1
        } else {
            level *= 0.82                                              // fast attack, ~0.5 s fade
        }
    }

    /// 8 frequency bands (low to high) from 1024 samples, using a Fourier transform.
    func spectrum(_ p: UnsafePointer<Float>, _ n: Int) -> [Float] {
        let size = 1024
        guard n >= size, let setup = fftSetup else { return [] }
        var window = [Float](repeating: 0, count: size)
        vDSP_hann_window(&window, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        var windowed = [Float](repeating: 0, count: size)
        vDSP_vmul(p, 1, window, 1, &windowed, 1, vDSP_Length(size))
        var real = [Float](repeating: 0, count: size / 2), imag = [Float](repeating: 0, count: size / 2)
        var mags = [Float](repeating: 0, count: size / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: size / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(size / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, 10, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(size / 2))
            }
        }
        let edges = [1, 3, 6, 12, 24, 48, 96, 160, 256]
        return (0..<8).map { b in
            let slice = mags[edges[b]..<edges[b + 1]]
            let avg = slice.reduce(0, +) / Float(slice.count)
            return min(1, (avg / 300).squareRoot())
        }
    }
}

/// Little dancing bars. Real sound if Spindle can hear it, a gentle demo pattern otherwise.
struct EqualizerBars: View {
    /// Height (0...1) of bar `i`: real sound when it can be heard, a gentle demo wave while playing, flat when paused.
    private func barLevel(_ i: Int, _ t: Double, _ live: Bool) -> Double {
        if live { return audio.bands[min(i * 8 / max(count, 1), 7)] }
        if !playing { return 0.1 }
        let phase: Double = t * (3.0 + Double(i)) + Double(i)
        return 0.35 + 0.3 * sin(phase)
    }

    @ObservedObject var audio: AudioLevel
    var playing: Bool
    var count: Int
    var rainbow: Bool
    var gain: Double
    var body: some View {
        // 30 fps instead of the display's refresh rate: visually the same, a fraction of the work.
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let live = tl.date.timeIntervalSince(audio.lastSample) < 1.5
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<count, id: \.self) { i in
                    let v = barLevel(i, t, live)
                    Capsule()
                        .fill(rainbow ? Color(hue: Double(i) / Double(max(count, 1)), saturation: 0.8, brightness: 1) : Color.white)
                        .frame(width: 3, height: 4 + 14 * max(0.05, min(1, v)))
                }
            }
        }
    }
}
