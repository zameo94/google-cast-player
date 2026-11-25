import Foundation

/// Keeps the Mac awake for as long as a cast is active.
@MainActor
protocol CastPowerAsserting: AnyObject {
    /// Whether an activity is currently held.
    var isActive: Bool { get }
    /// Starts holding the activity; calling it while it is already held does nothing.
    func begin()
    /// Releases the activity; calling it while it is not held does nothing.
    func end()
}

/// Holds one `ProcessInfo` activity for the duration of a cast.
///
/// `userInitiated` keeps macOS from putting the process into App Nap, which otherwise
/// coalesces timers and throttles network I/O as soon as the window is inactive or the
/// display sleeps. `idleSystemSleepDisabled` keeps the Mac from going to sleep on its
/// own. Together they keep the media server and the Cast connection reachable while the
/// display is off or the screen is locked.
///
/// Neither option prevents sleep when the lid closes: macOS always sleeps on lid close
/// unless the Mac runs in clamshell mode or `pmset disablesleep` is set, and no
/// application can override that. An interrupted cast is recovered after the wake
/// instead.
@MainActor
final class CastPowerAssertion: CastPowerAsserting {
    private var activity: NSObjectProtocol?

    var isActive: Bool {
        activity != nil
    }

    func begin() {
        guard activity == nil else {
            return
        }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Casting a video to a Cast device"
        )
    }

    func end() {
        guard let activity else {
            return
        }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }
}
