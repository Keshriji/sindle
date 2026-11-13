import Foundation
import ScreenCaptureKit
import Accelerate
import SwiftUI
import CoreMedia
import CoreGraphics

/// Listens to the Mac's system audio (not the microphone) and reports the beat of what is playing.
/// Needs Screen Recording permission (macOS lumps system-audio capture under it). Nothing is saved or sent anywhere.
///
/// Audio arrives roughly every 20 ms. Publishing for every buffer (and writing the eight bands one
/// at a time, which sends eight change notifications) is what made Spindle heavy and unresponsive,
/// so updates are throttled to 20 a second and the bands are published in a single assignment.
final class AudioLevel: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    /// 0...1 beat envelope: jumps to 1 on a detected beat and fades over about half a second. The
    /// Beat Glow reads this, so the light flashes with the kick instead of drifting on a guessed tempo.
    @Published var level = 0.0
    var lastSample = Date.distantPast         // read by the glow to know if live audio is arriving
    @Published var bands = [Double](repeating: 0, count: 8)
    /// True while macOS has not handed over Screen Recording yet, so capture cannot start.
    @Published var needsPermission = false

    private var stream: SCStream?
    private var starting = false
    private var lastPublish = Date.distantPast
    private var askedThisRun = false
    private var energy: [Double] = []          // recent low-band energy, used to find beats
    private var lastBeat = Date.distantPast
    private lazy var fftSetup = vDSP_create_fftsetup(10, FFTRadix(kFFTRadix2))

    func start() {
        guard stream == nil, !starting else { return }
        starting = true
        Task {
            // Ask at most once per run, and never while capture is already up: calling into
            // ScreenCaptureKit again and again is what made the permission sheet keep coming back
            // after it had been allowed. The ask blocks, so it stays off the main thread.
            if !CGPreflightScreenCaptureAccess() {
                if !askedThisRun { askedThisRun = true; _ = CGRequestScreenCaptureAccess() }
                await MainActor.run { self.needsPermission = true; self.starting = false }
                return
            }
            await MainActor.run { self.needsPermission = false }
            do {
                let content = try await SCShareableContent.current
                guard let display = content.displays.first else { await MainActor.run { self.starting = false }; return }
                let cfg = SCStreamConfiguration()
                cfg.capturesAudio = true
                cfg.excludesCurrentProcessAudio = true
                cfg.width = 2; cfg.height = 2                               // video is not used
                cfg.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                let s = SCStream(filter: SCContentFilter(display: display, excludingWindows: []),
                                 configuration: cfg, delegate: self)
                try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: DispatchQueue(label: "spindle.audio"))
                try await s.startCapture()
                await MainActor.run { self.stream = s; self.starting = false }
            } catch {
                // Permission went away or capture failed: the glow keeps its steady pulse.
                await MainActor.run { self.starting = false }
            }
        }
    }

    private var wanted = false
    private var hasMusic = false

    /// Capture runs only when something shows it (Beat Glow or the island equalizer) *and* music is
    /// playing. Starting it during launch meant a Screen Recording consent sheet before the island
    /// was usable, which looks exactly like a frozen app.
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

    /// Stops system-audio capture (and with it the Screen Recording indicator in the menu bar).
    func stop() {
        guard let s = stream else { return }
        stream = nil
        Task { try? await s.stopCapture() }
    }

    func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sb.isValid else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPublish) >= 0.05 else { return }   // at most 20 updates a second
        lastPublish = now

        var bandVals: [Float] = []
        try? sb.withAudioBufferList { abl, _ in
            for buf in abl {
                guard bandVals.isEmpty, let p = buf.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let n = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
                guard n > 0 else { continue }
                bandVals = self.spectrum(p, n)
            }
        }

        let bandSample = bandVals
        DispatchQueue.main.async {
            let set = SettingsStore.shared
            self.lastSample = Date()
            guard bandSample.count == 8 else { return }
            var next = self.bands
            for b in 0..<8 {
                let v = min(1, Double(bandSample[b]) * set.eqSensitivity)
                next[b] = v > next[b] ? v : next[b] * 0.82 + v * 0.18
            }
            self.bands = next                                   // one change notification, not eight

            // Beat: the bass rising above its own recent average. That is what puts the glow on the
            // kick drum instead of on a fixed tempo.
            let low = Double(bandSample[0])
            self.energy.append(low)
            if self.energy.count > 43 { self.energy.removeFirst() }         // about 2 s of history
            let avg = self.energy.reduce(0, +) / Double(self.energy.count)
            let now = Date()
            if low > max(avg * 1.4, 0.15), now.timeIntervalSince(self.lastBeat) > 0.22 {
                self.lastBeat = now
                self.level = 1
            } else {
                self.level *= 0.82                                          // fast attack, ~0.5 s fade
            }
        }
    }

    func stream(_ s: SCStream, didStopWithError error: Error) {}

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
                    let v: Double = live ? audio.bands[min(i * 8 / max(count, 1), 7)]
                                         : (playing ? 0.35 + 0.3 * sin(t * (3 + Double(i)) + Double(i)) : 0.1)
                    Capsule()
                        .fill(rainbow ? Color(hue: Double(i) / Double(max(count, 1)), saturation: 0.8, brightness: 1) : Color.white)
                        .frame(width: 3, height: 4 + 14 * max(0.05, min(1, v)))
                }
            }
        }
    }
}
