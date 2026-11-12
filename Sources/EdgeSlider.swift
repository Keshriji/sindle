import SwiftUI
import AppKit

/// A thin bar on the screen edge. Hover and it widens; drag it to change the value.
struct EdgeSlider: View {
    let icon: String
    let value: Double
    let onChange: (Double) -> Void
    @State private var hover = false
    @State private var dragging = false
    private let height: CGFloat = 180

    var body: some View {
        let wide = hover || dragging
        let filled: CGFloat = height * CGFloat(min(max(value, 0), 1))
        return ZStack(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.8))
            Rectangle().fill(Color.white.opacity(0.92)).frame(height: filled)
            Image(systemName: icon).font(.system(size: 13, weight: .medium))
                .foregroundStyle(value > 0.12 ? Color.black : Color.white)
                .padding(.bottom, 9).opacity(wide ? 1 : 0)
        }
        .frame(width: wide ? 30 : 6, height: height)
        .clipShape(RoundedRectangle(cornerRadius: wide ? 15 : 3))
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: wide)
        .onHover { hover = $0 }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { g in
                dragging = true
                let fraction = Double(min(max(g.location.y / height, 0), 1))
                onChange(1.0 - fraction)
            }
            .onEnded { _ in dragging = false })
    }
}

struct VolumeEdge: View {
    @ObservedObject var system: SystemControls
    var icon: String {
        switch system.volume {
        case 0: return "speaker.slash.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
    var body: some View {
        EdgeSlider(icon: icon, value: system.volume, onChange: system.setVolume)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(.leading, 4)
    }
}

struct BrightnessEdge: View {
    @ObservedObject var system: SystemControls
    var body: some View {
        EdgeSlider(icon: "sun.max.fill", value: system.brightness, onChange: system.setBrightness)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing).padding(.trailing, 4)
    }
}

final class EdgePanel: NSPanel {
    enum Side { case left, right }
    let side: Side

    init<V: View>(side: Side, content: V) {
        self.side = side
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        contentView = NSHostingView(rootView: content)
        reposition()
    }

    func reposition() {
        guard let f = NSScreen.main?.frame else { return }
        let w: CGFloat = 44, h: CGFloat = 200
        setFrame(NSRect(x: side == .left ? f.minX : f.maxX - w, y: f.midY - h / 2, width: w, height: h), display: true)
    }
    override var canBecomeKey: Bool { false }
}
