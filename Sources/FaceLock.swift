import SwiftUI
import AVFoundation
import Vision
import LocalAuthentication

/// Face Unlock (beta) for Spindle's private tabs (Tray, Notes, Tasks, Diary). It does NOT unlock the Mac.
/// Compares your face to photos taken at set-up using Apple's Vision feature prints.
/// This is a convenience lock, not strong security: a photo of you might fool it. Touch ID / password is always offered.
final class FaceLock: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = FaceLock()
    @Published var unlocked = false
    @Published var status = ""
    @Published var enrolled: Int
    @Published var threshold: Double { didSet { UserDefaults.standard.set(threshold, forKey: "s.faceThreshold") } }

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "spindle.face")
    private enum Mode { case idle, enrol(Int), verify }
    private var mode = Mode.idle
    private var prints: [VNFeaturePrintObservation]
    private var lastTick = Date.distantPast
    private var hits = 0
    private var started = Date()

    private override init() {
        let saved = UserDefaults.standard.array(forKey: "s.facePrints") as? [Data] ?? []
        prints = saved.compactMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: $0) }
        enrolled = prints.count
        threshold = UserDefaults.standard.object(forKey: "s.faceThreshold") as? Double ?? 0.5
        super.init()
    }

    // MARK: public
    func startEnrol() { prints = []; post("Look at the camera…", enrolled: 0); startCamera(.enrol(5)) }
    func startVerify() { guard enrolled > 0, !unlocked else { return }; post("Looking for you…"); startCamera(.verify) }
    func lock() { stopCamera(); post("", unlocked: false) }
    func resetFace() {
        prints = []; UserDefaults.standard.removeObject(forKey: "s.facePrints")
        stopCamera(); post("Face data removed", unlocked: false, enrolled: 0)
    }
    func usePassword() {
        NSApp.activate(ignoringOtherApps: true)
        let ctx = LAContext(); var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { post("No Touch ID or password available"); return }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Spindle's private tabs") { ok, _ in
            if ok { self.stopCamera(); self.post("Unlocked", unlocked: true) }
        }
    }

    // MARK: camera
    private func post(_ s: String, unlocked u: Bool? = nil, enrolled e: Int? = nil) {
        DispatchQueue.main.async {
            self.status = s
            if let u { self.unlocked = u }
            if let e { self.enrolled = e }
        }
    }
    private func startCamera(_ m: Mode) {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { self.post("Camera access is off"); return }
            self.queue.async {
                self.mode = m; self.hits = 0; self.started = Date()
                if self.session.inputs.isEmpty, let dev = AVCaptureDevice.default(for: .video),
                   let input = try? AVCaptureDeviceInput(device: dev), self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                if self.session.outputs.isEmpty {
                    self.output.alwaysDiscardsLateVideoFrames = true
                    self.output.setSampleBufferDelegate(self, queue: self.queue)
                    if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
                }
                if !self.session.isRunning { self.session.startRunning() }
            }
        }
    }
    private func stopCamera() { queue.async { self.mode = .idle; self.session.stopRunning() } }

    func captureOutput(_ o: AVCaptureOutput, didOutput sb: CMSampleBuffer, from c: AVCaptureConnection) {
        if case .idle = mode { return }
        guard Date().timeIntervalSince(lastTick) > 0.7, let pix = CMSampleBufferGetImageBuffer(sb) else { return }
        lastTick = Date()
        let faces = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pix, orientation: .up)
        try? handler.perform([faces])
        guard let box = faces.results?.max(by: { $0.boundingBox.width < $1.boundingBox.width })?.boundingBox,
              box.width > 0.15 else { timeoutCheck(); return }
        let fp = VNGenerateImageFeaturePrintRequest()
        fp.regionOfInterest = box
        try? handler.perform([fp])
        guard let obs = fp.results?.first as? VNFeaturePrintObservation else { return }

        switch mode {
        case .enrol(let left):
            prints.append(obs)
            if left <= 1 {
                UserDefaults.standard.set(prints.compactMap {
                    try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true) }, forKey: "s.facePrints")
                mode = .idle; session.stopRunning()
                post("Face saved. Turn on the lock in Settings.", enrolled: prints.count)
            } else {
                mode = .enrol(left - 1)
                post("Keep looking… \(5 - left + 1)/5", enrolled: prints.count)
            }
        case .verify:
            var best = Float.greatestFiniteMagnitude
            for p in prints { var d: Float = 0; if (try? p.computeDistance(&d, to: obs)) != nil { best = min(best, d) } }
            if Double(best) < threshold {
                hits += 1
                if hits >= 2 { mode = .idle; session.stopRunning(); post("Unlocked", unlocked: true) }
            } else { hits = 0; timeoutCheck() }
        case .idle: break
        }
    }
    private func timeoutCheck() {
        guard case .verify = mode, Date().timeIntervalSince(started) > 10 else { return }
        mode = .idle; session.stopRunning()
        post("No match. Use Touch ID or password.")
    }
}

struct LockedPage: View {
    @ObservedObject var face: FaceLock
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "faceid").font(.system(size: 26)).foregroundStyle(.white)
            Text(face.status.isEmpty ? "Private tabs are locked" : face.status)
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 8) {
                if face.enrolled > 0 { chip("Scan face") { face.startVerify() } }
                chip("Touch ID / password") { face.usePassword() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { face.startVerify() }
    }
    private func chip(_ t: String, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            Text(t).font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(.white.opacity(0.16)))
        }.buttonStyle(.plain)
    }
}
