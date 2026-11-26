import Foundation
import os
import UniformTypeIdentifiers

/// Serves one selected file over the local network for a casting session.
protocol MediaServing: Sendable {
    /// Starts serving `file` and returns the URL a receiver can fetch.
    func startServing(_ file: MediaFile) async throws -> URL
    /// Stops serving and releases the port.
    func stopServing()
}

extension LocalMediaServer: MediaServing {
    func startServing(_ file: MediaFile) async throws -> URL {
        try await start(file: file).url
    }

    func stopServing() {
        stop()
    }
}

/// Playback state as the interface needs it, independent of the Cast protocol.
struct PlaybackSnapshot: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case playing
        case paused
        case buffering
        case finished
        case failed
        case unknown
    }

    let status: Status
    /// Position the device reported, in seconds.
    let position: TimeInterval?
    /// Duration of the media, in seconds.
    let duration: TimeInterval?
    /// When this snapshot was received, so the interface can advance the position.
    let receivedAt: Date?
}

/// Device volume as the interface needs it, independent of the Cast protocol.
struct DeviceVolume: Equatable, Sendable {
    /// Current level, from 0 to 1.
    let level: Double
    /// Whether the device is muted.
    let muted: Bool
}

/// A connected Cast session that can receive media.
@MainActor
protocol CastMediaLoading: AnyObject {
    /// Whether a session is open and ready for a load command.
    var isConnected: Bool { get }
    /// Asks the running receiver to load `media`.
    func load(_ media: CastClient.Media) async throws
    /// Reopens the session with the device the cast belongs to, after the transport died.
    func reconnect() async
    /// Position, in seconds, the cast reached, so a resumed cast continues where it stopped.
    var resumePosition: TimeInterval? { get }
}

/// Drives one casting session: serve the file locally, then ask the device to play it.
///
/// The model owns the server lifetime, so the file is reachable exactly while a cast is
/// active, and it stops serving when the cast ends or fails. It also owns the wake
/// assertion: while a cast runs the Mac is kept out of App Nap and out of idle sleep, so
/// locking the screen or letting the display turn off does not end the session.
///
/// A cast that loses its connection becomes `interrupted` instead of disappearing: the
/// file and the last position are kept, and the session is resumed automatically after
/// the Mac wakes or when the user asks for it.
@MainActor
@Observable
final class PlaybackModel {
    enum State: Equatable {
        /// Nothing is being cast.
        case idle
        /// The server is starting or the device is being asked to load.
        case starting
        /// The device accepted the media URL.
        case casting(url: URL)
        /// The client lost the device; the cast can be resumed where it stopped.
        case interrupted(reason: String)
        /// The cast could not start; the message is ready for display.
        case failed(String)
    }

    private(set) var state: State = .idle
    /// File of the current cast, kept so an interrupted cast can be resumed.
    private(set) var file: MediaFile?

    /// URL the receiver was asked to load, while a cast is active.
    var castingURL: URL? {
        guard case let .casting(url) = state else {
            return nil
        }
        return url
    }

    private let server: any MediaServing
    private let power: any CastPowerAsserting
    private let sleepWatcher: any SystemSleepWatching
    private let sleeper: any Sleeping
    /// Session of the current cast, used to resume it after the Mac wakes.
    private weak var connection: (any CastMediaLoading)?
    private var isWatchingForWake = false

    init(
        server: any MediaServing = LocalMediaServer(),
        power: any CastPowerAsserting = CastPowerAssertion(),
        sleepWatcher: any SystemSleepWatching = SystemSleepWatcher(),
        sleeper: any Sleeping = TaskSleeper()
    ) {
        self.server = server
        self.power = power
        self.sleepWatcher = sleepWatcher
        self.sleeper = sleeper
    }

    /// Starts reporting wakes; the application calls it once the interface exists.
    func startWatchingForWake() {
        guard !isWatchingForWake else {
            return
        }
        isWatchingForWake = true
        sleepWatcher.onWake = { [weak self] in
            guard let self else {
                return
            }
            Task { await self.handleWake() }
        }
        sleepWatcher.start()
    }
    /// Serves `file` locally and asks the device to play it.
    ///
    /// - Parameter startAt: Position, in seconds, the receiver starts from.
    func play(
        file: MediaFile,
        connection: any CastMediaLoading,
        startAt position: TimeInterval = 0
    ) async {
        guard connection.isConnected else {
            CastLog.playback.error("Play refused: the session is not connected")
            state = .failed("Connect to a device before casting.")
            return
        }

        stop()
        state = .starting
        self.file = file
        self.connection = connection
        power.begin()
        CastLog.playback.info(
            "Play requested: \(file.name, privacy: .public) from \(position, privacy: .public)s"
        )

        do {
            let url = try await server.startServing(file)
            let media = CastClient.Media(
                contentURL: url,
                contentType: Self.contentType(for: file),
                title: file.name,
                currentTime: position
            )
            try await connection.load(media)
            state = .casting(url: url)
            CastLog.playback.info("Cast started on port \(url.port ?? 0, privacy: .public)")
        } catch {
            release()
            state = .failed(Self.message(for: error))
            CastLog.playback.error("Cast failed: \(Self.message(for: error), privacy: .public)")
        }
    }

    /// Stops serving the file and forgets the cast.
    func stop() {
        if case .casting = state {
            CastLog.playback.info("Cast stopped on request")
        }
        release()
        file = nil
        connection = nil
        state = .idle
    }

    /// Marks the cast as stopped because the session was lost, keeping it resumable.
    ///
    /// Only a running cast is interrupted: a connection that fails before or after one is
    /// the connection model's own state, not a playback state. The wake assertion stays
    /// held on purpose: the Mac must not go to sleep before the recovery had a chance to
    /// run, which is exactly what used to turn a short loss into a dead session.
    func interrupt(reason: String) {
        guard case .casting = state else {
            return
        }
        server.stopServing()
        state = .interrupted(reason: reason)
        CastLog.playback.error("Cast interrupted: \(reason, privacy: .public)")
    }

    /// Reconnects to the device and reloads the file where the cast stopped.
    func resume() async {
        guard case let .interrupted(reason) = state,
              let file,
              let connection else {
            return
        }
        // A little context repeated, so the resume does not drop the viewer into the
        // middle of a scene.
        let position = connection.resumePosition.map { max(0, $0 - Self.resumeRewind) }
        state = .starting
        CastLog.playback.info("Resuming at \(position ?? 0, privacy: .public)s")

        await connection.reconnect()
        guard case .starting = state else {
            // The user stopped the cast while the session was reconnecting.
            CastLog.playback.info("Resume abandoned: the cast was stopped")
            return
        }
        guard connection.isConnected else {
            state = .interrupted(reason: Self.cannotReconnectMessage(from: reason))
            CastLog.playback.error("Resume failed: the device did not answer")
            return
        }
        await play(file: file, connection: connection, startAt: position ?? 0)
    }

    /// Stops the playing media and stops serving the file, keeping the session open.
    func stopPlayback(connection: CastConnectionModel) async {
        await connection.stopPlayback()
        stop()
    }

    /// MIME type the receiver should use for `file`.
    static func contentType(for file: MediaFile) -> String {
        guard let fileExtension = file.format.fileExtension,
              let type = UTType(filenameExtension: fileExtension)?.preferredMIMEType else {
            return "video/mp4"
        }
        return type
    }

    // MARK: - Recovery

    /// Resumes the interrupted cast after a wake, retrying while the network comes back.
    func handleWake() async {
        CastLog.playback.info("Mac woke")
        await recoverCast()
    }

    /// Reconnects an interrupted cast, retrying while the network comes back.
    ///
    /// The wake assertion is taken again before the attempts, so the Mac stays awake while
    /// the session is re-established, and it is released only when recovery gives up.
    func recoverCast() async {
        guard case .interrupted = state else {
            return
        }
        power.begin()

        var attempt = 1
        while true {
            if attempt > 1 {
                await sleeper.sleep(for: Self.retryDelay)
            }
            guard case .interrupted = state else {
                // The user stopped the cast or a wake recovered it first.
                return
            }
            await resume()
            guard case .interrupted = state else {
                return
            }
            guard attempt < Self.recoveryAttempts else {
                break
            }
            attempt += 1
        }

        power.end()
        CastLog.playback.error(
            "Recovery gave up after \(Self.recoveryAttempts, privacy: .public) attempts"
        )
    }

    // MARK: - Helpers

    private func release() {
        server.stopServing()
        power.end()
    }

    private static func cannotReconnectMessage(from reason: String) -> String {
        "The device did not answer after the connection was lost. Resume again, or connect again. \(reason)"
    }

    /// Seconds before the stop position that a resumed cast starts from.
    static let resumeRewind: TimeInterval = 3
    private static let recoveryAttempts = 3
    private static let retryDelay = Duration.seconds(2)

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
