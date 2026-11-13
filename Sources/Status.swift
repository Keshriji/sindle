import Foundation
import IOKit.ps

struct Headphones: Equatable {
    var name: String
    var left: Int?, right: Int?, caseLevel: Int?, main: Int?
}
struct Toast: Equatable { let icon: String; let text: String; var battery: Int? = nil; var charging = false }

/// Headphone battery, Mac battery/charging, and Focus mode. Shows a short toast in the island on changes.
final class StatusStore: ObservableObject {
    @Published var headphones: Headphones?
    @Published var charging = false
    @Published var batteryPercent: Int?
    @Published var focus: String?
    @Published var toast: Toast?
    private var timers: [Timer] = []
    private var toastWork: DispatchWorkItem?
    private var quiet = true          // no toasts for the first few seconds after launch

    func start() {
        readPower(); pollBluetooth(); pollFocus()
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<StatusStore>.fromOpaque(ctx).takeUnretainedValue().readPower()
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
        }
        timers = [
            Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.pollBluetooth() },
            Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.pollFocus() }
        ]
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.quiet = false }
    }

    func show(_ t: Toast) {
        guard !quiet, SettingsStore.shared.toastsOn else { return }
        toastWork?.cancel()
        toast = t
        let w = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
    }

    // MARK: power
    func readPower() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        var pct: Int?
        for ps in list {
            if let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
               let cur = d[kIOPSCurrentCapacityKey] as? Int { pct = cur }
        }
        var type = ""
        if let t = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() { type = t as String }
        let ac = (type == kIOPSACPowerValue)
        let was = charging
        batteryPercent = pct
        charging = ac
        if ac != was {
            show(Toast(icon: ac ? "bolt.fill" : "battery.50",
                       text: ac ? "Charging \(pct ?? 0)%" : "On battery \(pct ?? 0)%",
                       battery: pct ?? 0, charging: ac))
        }
    }

    // MARK: Bluetooth (system_profiler lists battery levels of connected devices)
    func pollBluetooth() {
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            p.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
            guard (try? p.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            func pct(_ v: Any?) -> Int? { (v as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) } }
            var found: Headphones?
            if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let arr = root["SPBluetoothDataType"] as? [[String: Any]],
               let connected = arr.first?["device_connected"] as? [[String: Any]] {
                outer: for entry in connected {
                    for (name, v) in entry {
                        guard let d = v as? [String: Any] else { continue }
                        let hp = Headphones(name: name,
                                            left: pct(d["device_batteryLevelLeft"]),
                                            right: pct(d["device_batteryLevelRight"]),
                                            caseLevel: pct(d["device_batteryLevelCase"]),
                                            main: pct(d["device_batteryLevelMain"]))
                        if hp.left != nil || hp.main != nil || (d["device_minorType"] as? String) == "Headphones" {
                            found = hp; break outer
                        }
                    }
                }
            }
            DispatchQueue.main.async { self.setHeadphones(found) }
        }
    }

    private func setHeadphones(_ hp: Headphones?) {
        let appeared = headphones == nil && hp != nil
        if headphones != hp { headphones = hp }
        if appeared, let hp {
            let level = hp.left ?? hp.main
            show(Toast(icon: "headphones", text: "\(hp.name)" + (level.map { " \($0)%" } ?? " connected")))
        }
    }

    // MARK: Focus (needs Full Disk Access to read the Focus database)
    func pollFocus() {
        DispatchQueue.global(qos: .utility).async {
            let dir = NSHomeDirectory() + "/Library/DoNotDisturb/DB/"
            var name: String?
            if let d = FileManager.default.contents(atPath: dir + "Assertions.json"),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let data = j["data"] as? [[String: Any]],
               let recs = data.first?["storeAssertionRecords"] as? [[String: Any]],
               let rec = recs.first {
                let id = ((rec["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String) ?? ""
                name = Self.focusName(id, dir)
            }
            DispatchQueue.main.async {
                guard self.focus != name else { return }
                let was = self.focus
                self.focus = name
                if let n = name, was == nil { self.show(Toast(icon: "moon.fill", text: n)) }
            }
        }
    }

    private static func focusName(_ id: String, _ dir: String) -> String {
        if let d = FileManager.default.contents(atPath: dir + "ModeConfigurations.json"),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let data = j["data"] as? [[String: Any]],
           let cfg = data.first?["modeConfigurations"] as? [String: Any],
           let mode = (cfg[id] as? [String: Any])?["mode"] as? [String: Any],
           let n = mode["name"] as? String { return n }
        return id.contains("donotdisturb") ? "Do Not Disturb" : "Focus"
    }
}
