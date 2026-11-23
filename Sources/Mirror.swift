import SwiftUI
import AVFoundation

/// Front-camera mirror. The camera only runs while it is on screen, and it says why if it cannot start.
final class MirrorNSView: NSView {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "spindle.mirror")      // start and stop share one queue, so a quick close cannot leave the camera on
    private lazy var preview = AVCaptureVideoPreviewLayer(session: session)
    var onStatus: (String) -> Void = { _ in }

    /// The Mac's own camera first, so a nearby iPhone (Continuity Camera) is not picked by mistake.
    static func pickCamera() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); preview.frame = bounds }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            onStatus("Allow camera access…")
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async {
                    if ok { self.run() } else { self.onStatus("Camera access is off. Turn it on under Privacy and Permissions.") }
                }
            }
        default:
            onStatus("Camera access is off. Turn it on under Privacy and Permissions.")
        }
    }

    private func run() {
        onStatus("Starting camera…")
        queue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .medium
            if self.session.inputs.isEmpty {
                guard let device = Self.pickCamera(),
                      let input = try? AVCaptureDeviceInput(device: device),
                      self.session.canAddInput(input) else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.onStatus("No camera found.") }
                    return
                }
                self.session.addInput(input)
            }
            self.session.commitConfiguration()
            self.session.startRunning()
            let running = self.session.isRunning
            DispatchQueue.main.async {
                if running {
                    if let c = self.preview.connection, c.isVideoMirroringSupported {
                        c.automaticallyAdjustsVideoMirroring = false
                        c.isVideoMirrored = true                       // behaves like a real mirror
                    }
                    self.onStatus("")
                } else {
                    self.onStatus("The camera would not start. Another app may be using it.")
                }
            }
        }
    }

    func stop() { queue.async { if self.session.isRunning { self.session.stopRunning() } } }
}

struct MirrorPreview: NSViewRepresentable {
    var onStatus: (String) -> Void = { _ in }
    func makeNSView(context: Context) -> MirrorNSView {
        let v = MirrorNSView(frame: .zero)
        v.onStatus = onStatus
        v.start()
        return v
    }
    func updateNSView(_ v: MirrorNSView, context: Context) {}
    static func dismantleNSView(_ v: MirrorNSView, coordinator: ()) { v.stop() }
}

/// The camera with its status message on top, used in the round Mirror button and the card page.
struct MirrorCircle: View {
    @State private var status = ""
    var body: some View {
        ZStack {
            MirrorPreview(onStatus: { status = $0 })
            if !status.isEmpty {
                Text(status).font(.system(size: 10)).multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85)).padding(10)
            }
        }
    }
}

struct MirrorPage: View {
    var body: some View {
        MirrorCircle()
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.2), lineWidth: 1))
    }
}
