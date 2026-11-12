import SwiftUI
import AppKit

/// How the island sits at the top of the screen.
enum IslandShape: String, CaseIterable, Identifiable {
    case classic, floating
    var id: String { rawValue }
    var title: String { self == .classic ? "Classic" : "Floating" }
}

/// What the island is made of.
enum IslandFinish: String, CaseIterable, Identifiable {
    case glass, mirror
    var id: String { rawValue }
    var title: String { self == .glass ? "Black Glass" : "Mirror" }
}

/// Island look, remembered between launches. Everything here is drawn in code: no bundled or
/// third-party artwork, animations or wallpapers.
final class Look: ObservableObject {
    @Published var shape: IslandShape { didSet { save() } }
    @Published var finish: IslandFinish { didSet { save() } }

    init() {
        let d = UserDefaults.standard
        shape = IslandShape(rawValue: d.string(forKey: "spindle.shape") ?? "") ?? .classic
        finish = IslandFinish(rawValue: d.string(forKey: "spindle.finish") ?? "") ?? .glass
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(shape.rawValue, forKey: "spindle.shape")
        d.set(finish.rawValue, forKey: "spindle.finish")
    }

    /// Floating sits a little below the very top edge, so its corners are visible.
    var topInset: CGFloat { shape == .classic ? 0 : 10 }
    var topCorners: CGFloat { shape == .classic ? 0 : 16 }

    var fill: AnyShapeStyle {
        switch finish {
        case .glass:
            return AnyShapeStyle(Color.black)
        case .mirror:
            return AnyShapeStyle(LinearGradient(colors: [Color(white: 0.46), Color(white: 0.05)],
                                                startPoint: .top, endPoint: .bottom))
        }
    }
}
