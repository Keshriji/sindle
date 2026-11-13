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
