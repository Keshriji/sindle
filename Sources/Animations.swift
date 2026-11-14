import SwiftUI

/// Battery that fills up when it appears, with a pulsing bolt and a soft glow while charging.
struct BatteryView: View {
    let percent: Int
    let charging: Bool
    @State private var shown = 0.0
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 2) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.7), lineWidth: 1.5).frame(width: 28, height: 14)
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(percent <= 20 && !charging ? Color.red : Color.green)
                    .frame(width: max(2, 24 * shown), height: 10).padding(.leading, 2)
                if charging {
                    Image(systemName: "bolt.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 28).scaleEffect(pulse ? 1.3 : 0.9)
                }
            }
            .shadow(color: Color.green.opacity(charging ? (pulse ? 0.9 : 0.2) : 0), radius: 6)
            RoundedRectangle(cornerRadius: 1).fill(.white.opacity(0.7)).frame(width: 2, height: 6)
        }
        .onAppear {
            shown = 0
            withAnimation(.easeOut(duration: 0.9)) { shown = Double(percent) / 100 }
            if charging { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true } }
        }
        .onChange(of: percent) { _, n in withAnimation(.easeOut(duration: 0.5)) { shown = Double(n) / 100 } }
    }
}

/// Buttons squish a little when pressed.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// Icon that pops in with a spring.
struct PopIcon: View {
    let name: String
    @State private var on = false
    var body: some View {
        Image(systemName: name).foregroundStyle(.white)
            .scaleEffect(on ? 1 : 0.3).opacity(on ? 1 : 0)
            .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { on = true } }
    }
}

/// Alarm bell that shakes.
struct ShakeIcon: View {
    let name: String
    @State private var shake = false
    var body: some View {
        Image(systemName: name).foregroundStyle(.yellow)
            .rotationEffect(.degrees(shake ? 16 : -16))
            .onAppear { withAnimation(.easeInOut(duration: 0.09).repeatCount(24, autoreverses: true)) { shake = true } }
    }
}

/// A CD: the album cover is the disc, with a centre hole, a bright rim and a fixed shine while it turns.
struct CDDisc: View {
    let url: URL?
    var size: CGFloat = 26
    var playing = true
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { tl in
            let angle = playing ? (tl.date.timeIntervalSinceReferenceDate * 150).truncatingRemainder(dividingBy: 360) : 0
            ZStack {
                ZStack {
                    AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.4) }
                        .frame(width: size, height: size).clipShape(Circle())
                    Circle().fill(.black).frame(width: size * 0.22)
                    Circle().stroke(.white.opacity(0.45), lineWidth: 0.6).frame(width: size * 0.22)
                }
                .rotationEffect(.degrees(angle))
                Circle().fill(AngularGradient(colors: [.white.opacity(0.35), .clear, .white.opacity(0.22), .clear, .white.opacity(0.35)], center: .center))
                    .frame(width: size, height: size)
                Circle().stroke(.white.opacity(0.4), lineWidth: 0.6).frame(width: size, height: size)
            }
            .frame(width: size, height: size)
        }
    }
}

/// Thin level bar used by the volume and brightness pop-ups.
struct HUDBar: View {
    let level: Double
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.25))
            Capsule().fill(.white).frame(width: 44 * max(0.04, min(1, level)))
        }
        .frame(width: 44, height: 5)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: level)
    }
}
