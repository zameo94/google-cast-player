import AppKit

/// Reports when the Mac wakes from sleep.
@MainActor
protocol SystemSleepWatching: AnyObject {
    /// Called on the main actor right after the Mac wakes.
    var onWake: (() -> Void)? { get set }
    /// Starts reporting; calling it again does nothing.
    func start()
}

/// Watches the workspace for a wake and forwards it to the playback model.
///
/// The watcher is owned by the playback model, which lives for the application lifetime,
/// so the notification observer is never removed.
@MainActor
final class SystemSleepWatcher: SystemSleepWatching {
    var onWake: (() -> Void)?
    private var observer: NSObjectProtocol?

    func start() {
        guard observer == nil else {
            return
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onWake?()
            }
        }
    }
}
