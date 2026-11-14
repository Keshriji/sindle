import Foundation
import IOKit.pwr_mgt

/// Keeps the display awake while music is playing, if the setting is on.
/// Uses a single power assertion and releases it as soon as playback stops.
final class ScreenKeeper {
    private var assertion: IOPMAssertionID = 0

    func setActive(_ on: Bool) {
        if on {
            guard assertion == 0 else { return }
            var id: IOPMAssertionID = 0
            let reason = "Spindle is playing music" as CFString
            if IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString,
                                           IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           reason, &id) == kIOReturnSuccess {
                assertion = id
            }
        } else if assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
    }

    deinit { if assertion != 0 { IOPMAssertionRelease(assertion) } }
}
