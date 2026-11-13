import SwiftUI
import AVFoundation

/// Front-camera mirror. The camera only runs while this page is open.
final class MirrorNSView: NSView {
    private let session = AVCaptureSession()
    private lazy var preview = AVCaptureVideoPreviewLayer(session: session)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); preview.frame = bounds }

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { ok in
            guard ok else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                if self.session.inputs.isEmpty,
                   let dev = AVCaptureDevice.default(for: .video),
                   let input = try? AVCaptureDeviceInput(device: dev), self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                self.session.startRunning()
                DispatchQueue.main.async {
                    if let c = self.preview.connection {
                        c.automaticallyAdjustsVideoMirroring = false
                        c.isVideoMirrored = true                     // behaves like a real mirror
                    }
                }
            }
        }
    }
    func stop() { DispatchQueue.global().async { self.session.stopRunning() } }
}

struct MirrorPreview: NSViewRepresentable {
    func makeNSView(context: Context) -> MirrorNSView { let v = MirrorNSView(frame: .zero); v.start(); return v }
    func updateNSView(_ v: MirrorNSView, context: Context) {}
    static func dismantleNSView(_ v: MirrorNSView, coordinator: ()) { v.stop() }
}

struct MirrorPage: View {
    var body: some View {
        MirrorPreview()
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.2), lineWidth: 1))
    }
}
