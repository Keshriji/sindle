import AppKit

/// Original key-click sounds played from the macOS system sound bank, so no audio is bundled or copied.
/// Sets are just different pairs of system sounds; the first plays on key-down, the second on key-up.
final class KeySoundEngine {
    static let shared = KeySoundEngine()

    private static let sets: [[String]] = [
        ["Tink", "Pop"],        // Office
        ["Morse", "Funk"],      // Retro
        ["Bottle", "Ping"]      // Soft
    ]

    private var down = true
    private var last = Date.distantPast

    func play() {
        let now = Date()
        guard now.timeIntervalSince(last) > 0.012 else { return }
        last = now

        let set = SettingsStore.shared.keySoundSet
        let names = Self.sets[min(max(set, 0), Self.sets.count - 1)]
        let name = down ? names[0] : names[min(1, names.count - 1)]
        down.toggle()

        guard let sound = NSSound(named: name) else { return }
        sound.volume = Float(SettingsStore.shared.keySoundVolume)
        sound.play()
    }
}
