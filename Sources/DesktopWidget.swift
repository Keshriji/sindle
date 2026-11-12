import SwiftUI
import AppKit

/// A turntable or colour "aura" that sits on the desktop. Click it to switch style; drag it to move it.
final class DesktopWidgetPanel: NSPanel {
    init(player: NowPlaying) {
        super.init(contentRect: NSRect(x: 80, y: 120, width: 220, height: 220),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isMovableByWindowBackground = true
        contentView = NSHostingView(rootView: DesktopWidgetView(player: player))
    }
}

struct DesktopWidgetView: View {
    @ObservedObject var player: NowPlaying
    @State private var style = 0
    private var playing: Bool { player.track != nil }

    var body: some View {
        ZStack { Group { if style == 0 { turntable } else if style == 1 { sleeve } else { aura } } }
            .frame(width: 220, height: 220)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { style = (style + 1) % 3 } }
    }

    private var cover: some View {
        AsyncImage(url: player.track?.artworkURL) { $0.resizable().scaledToFill() }
            placeholder: { Color.gray.opacity(0.4) }
    }

    private var turntable: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20).fill(Color(red: 0.16, green: 0.11, blue: 0.08))
            ZStack {
                Circle().fill(.black)
                ForEach([62, 76, 90], id: \.self) { r in Circle().stroke(.white.opacity(0.08), lineWidth: 1).frame(width: CGFloat(r) * 2) }
                cover.frame(width: 70, height: 70).clipShape(Circle())
                Circle().fill(.black).frame(width: 8)
            }
            .frame(width: 190, height: 190)
            .rotationEffect(.degrees(playing ? 360 : 0))
            .animation(playing ? .linear(duration: 3).repeatForever(autoreverses: false) : .default, value: playing)
            Capsule().fill(.white.opacity(0.85)).frame(width: 8, height: 100)
                .offset(y: -40).rotationEffect(.degrees(playing ? 18 : -8), anchor: .top)
                .offset(x: 84, y: -48)
                .animation(.spring(response: 0.6, dampingFraction: 0.6), value: playing)
        }
    }

    private var sleeve: some View {
        ZStack {
            Circle().fill(.black).frame(width: 150, height: 150)
                .overlay(Circle().fill(.red.opacity(0.8)).frame(width: 40))
                .rotationEffect(.degrees(playing ? 360 : 0))
                .animation(playing ? .linear(duration: 3).repeatForever(autoreverses: false) : .default, value: playing)
                .offset(x: playing ? 48 : 0)
            cover.frame(width: 150, height: 150).clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 12).offset(x: playing ? -30 : 0)
        }.animation(.spring(response: 0.6, dampingFraction: 0.7), value: playing)
    }

    private var aura: some View {
        ZStack {
            cover.frame(width: 200, height: 200).blur(radius: 50).opacity(0.9)
            cover.frame(width: 120, height: 120).clipShape(RoundedRectangle(cornerRadius: 16)).shadow(radius: 20)
        }
    }
}
