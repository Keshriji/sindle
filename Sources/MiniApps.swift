import SwiftUI
import Combine
import Foundation

/// State for the island's small utilities, kept between page switches.
final class MiniStore: ObservableObject {
    @Published var picked = 0
    @Published var running = false
    @Published var elapsed = 0.0
    @Published var dice = 1
    @Published var heads = true
    @Published var pick = "🎲"

    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, self.running else { return }
            self.elapsed += 0.1
        }
    }

    func toggle() { running.toggle() }
    func reset() { running = false; elapsed = 0 }
    func roll() { dice = Int.random(in: 1...6) }
    func flip() { heads = Bool.random() }
    func choose() { pick = ["🎲", "🎯", "🚀", "🌙", "⭐️", "🎸", "🍀", "🔥"].randomElement() ?? "🎲" }
}

struct MiniAppsPage: View {
    @ObservedObject var mini: MiniStore
    private let names = ["Stopwatch", "Dice", "Coin", "Pick"]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(0..<names.count, id: \.self) { i in
                    Button { mini.picked = i } label: {
                        Text(names[i])
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(mini.picked == i ? 1 : 0.45))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(.white.opacity(mini.picked == i ? 0.16 : 0)))
                    }.buttonStyle(.plain)
                }
                Spacer()
            }

            Group {
                switch mini.picked {
                case 0: stopwatch
                case 1: dice
                case 2: coin
                default: picker
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var stopwatch: some View {
        let m = Int(mini.elapsed) / 60
        let s = mini.elapsed.truncatingRemainder(dividingBy: 60)
        return VStack(spacing: 10) {
            Text(String(format: "%02d:%04.1f", m, s))
                .font(.system(size: 30, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            HStack(spacing: 14) {
                chip(mini.running ? "Pause" : "Start") { mini.toggle() }
                chip("Reset") { mini.reset() }
            }
        }
    }

    private var dice: some View {
        VStack(spacing: 10) {
            Text("\(mini.dice)")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            chip("Roll") { mini.roll() }
        }
    }

    private var coin: some View {
        VStack(spacing: 10) {
            Text(mini.heads ? "Heads" : "Tails")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            chip("Flip") { mini.flip() }
        }
    }

    private var picker: some View {
        VStack(spacing: 10) {
            Text(mini.pick)
                .font(.system(size: 46, design: .rounded))
            chip("Pick one") { mini.choose() }
        }
    }

    private func chip(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(Capsule().fill(.white.opacity(0.15)))
        }.buttonStyle(.plain)
    }
}
