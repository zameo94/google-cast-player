import Foundation
import os
import Network

/// A Cast session that can be started and stopped, as the connection state needs it.
///
/// The protocol exists so the connection state can be exercised without a device; the
/// real implementation is `CastClient` over a TLS transport.
@MainActor
protocol CastSessionControlling: AnyObject {
    /// Connects to the device and starts its receiver.
    ///
    /// - Returns: The transport id of the running receiver.
    func start() async throws -> String
    /// Media status the receiver reports, when the session calls back.
    var onMediaStatusChange: ((CastClient.MediaStatus?) -> Void)? { get set }
    /// Called when the device reports that its receiver stopped.
    var onReceiverStopped: (() -> Void)? { get set }
    /// Called when the transport stops carrying the session, for example after a sleep.
    var onConnectionEnded: (() -> Void)? { get set }
    /// Volume the receiver reports, when the session calls back.
    var onVolumeChange: ((CastClient.Volume?) -> Void)? { get set }
    /// Sets the device volume, from 0 to 1.
    func setVolume(_ level: Double) async
    /// Mutes or unmutes the device.
    func setMuted(_ muted: Bool) async
    /// Asks the running receiver to load `media`.
    func loadMedia(_ media: CastClient.Media, transportID: String) async throws
    /// Resumes the paused media.
    func resumePlayback() async
    /// Pauses the playing media.
    func pausePlayback() async
    /// Moves the media to `position`, in seconds.
    func seekPlayback(to position: TimeInterval) async
    /// Stops the playing media and keeps the session open.
    func stopMediaPlayback() async
    /// Ends the session: stops the media and the receiver, then closes.
    func stop() async
}

extension CastClient: CastSessionControlling {
    func start() async throws -> String {
        try await connect()
        return try await launchDefaultReceiver()
    }

    var onMediaStatusChange: ((CastClient.MediaStatus?) -> Void)? {
        get { onMediaStatus }
        set { onMediaStatus = newValue }
    }

    func loadMedia(_ media: CastClient.Media, transportID: String) async throws {
        try await load(media, transportID: transportID)
    }

    func resumePlayback() async {
        await play()
    }

    func pausePlayback() async {
        await pause()
    }

    func seekPlayback(to position: TimeInterval) async {
        await seek(to: position)
    }

    func stopMediaPlayback() async {
        await stopMedia()
    }

    func stop() async {
        await endSession()
    }
}

/// Application state for the connection to one Cast device.
///
/// The model reports what really happened: it moves to `connected` only after the device
/// answered the handshake and started its receiver, and to `failed` with the reported
/// reason otherwise. It never shows a state the device did not confirm.
@MainActor
@Observable
final class CastConnectionModel {
    enum State: Equatable {
        /// No device is selected for a session.
        case idle
        /// The transport is opening or the receiver is starting.
        case connecting
        /// The device confirmed the session.
        case connected
        /// The session ended with a reason ready for display.
        case failed(String)
    }

    private(set) var state: State = .idle
    /// Device the current state refers to.
    private(set) var connectedDevice: CastDevice?
    /// Receiver transport id the load and playback commands are addressed to.
    private(set) var receiverTransportID: String?
    /// Last media status the receiver reported.
    private(set) var mediaStatus: CastClient.MediaStatus?
    /// When `mediaStatus` was received, used to advance the displayed position.
    private(set) var mediaStatusReceivedAt: Date?
    /// Volume the receiver last reported, in app types.
    private(set) var volume: DeviceVolume?
    /// Position, in seconds, the cast reached, kept after the status is cleared so an
    /// interrupted cast can be resumed where it stopped.
    private(set) var resumePosition: TimeInterval?

    /// Playback state for the interface, in app types.
    var playbackSnapshot: PlaybackSnapshot? {
        guard let mediaStatus else {
            return nil
        }
        let status: PlaybackSnapshot.Status = switch mediaStatus.playerState {
        case .playing: .playing
        case .paused: .paused
        case .buffering: .buffering
        case .idle: mediaStatus.idleReason == "ERROR" ? .failed : .finished
        case .unknown: .unknown
        }
        return PlaybackSnapshot(
            status: status,
            position: mediaStatus.position,
            duration: mediaStatus.duration,
            receivedAt: mediaStatusReceivedAt
        )
    }

    /// Position the media reached, including the time elapsed since the last report.
    var livePosition: TimeInterval? {
        guard let mediaStatus, let position = mediaStatus.position else {
            return nil
        }
        var value = position
        if mediaStatus.playerState == .playing, let mediaStatusReceivedAt {
            value += Date().timeIntervalSince(mediaStatusReceivedAt)
        }
        if let duration = mediaStatus.duration, value > duration {
            value = duration
        }
        return value
    }

    private let makeSession: (NWEndpoint) -> any CastSessionControlling
    private var session: (any CastSessionControlling)?
    private var attempt = 0

    init(
        makeSession: @escaping (NWEndpoint) -> any CastSessionControlling = { endpoint in
            CastClient(transport: TLSCastTransport(endpoint: endpoint))
        }
    ) {
        self.makeSession = makeSession
    }

    /// Opens a session with `device` and starts its receiver.
    ///
    /// Connecting to the device that is already connected is a no-op, so a stray tap
    /// never tears down a running session.
    func connect(to device: CastDevice) async {
        await connect(to: device, force: false)
    }

    /// Opens a new session with the device of the current session, even when the model
    /// still believes it is connected.
    ///
    /// Used after the transport died, for example when the Mac woke from sleep: the old
    /// socket cannot be reused, so a fresh session carries the cast again.
    func reconnect() async {
        guard let device = connectedDevice else {
            return
        }
        await connect(to: device, force: true)
    }

    private func connect(to device: CastDevice, force: Bool) async {
        if !force, state == .connected, connectedDevice?.id == device.id {
            return
        }
        guard let endpoint = device.endpoint else {
            connectedDevice = device
            state = .failed("This device cannot be reached yet. Search again to refresh it.")
            return
        }

        await stopSession()
        attempt += 1
        let currentAttempt = attempt
        // A position belongs to the device and file it came from; a different device
        // starts from the beginning.
        if connectedDevice?.id != device.id {
            resumePosition = nil
        }
        connectedDevice = device
        receiverTransportID = nil
        volume = nil
        state = .connecting

        let session = makeSession(endpoint)
        session.onMediaStatusChange = { [weak self] status in
            self?.apply(status)
        }
        session.onReceiverStopped = { [weak self] in
            self?.receiverStopped()
        }
        session.onConnectionEnded = { [weak self] in
            self?.connectionLost()
        }
        session.onVolumeChange = { [weak self] volume in
            self?.volume = volume.map { DeviceVolume(level: $0.level, muted: $0.muted) }
        }
        self.session = session

        do {
            let transportID = try await session.start()
            guard currentAttempt == attempt else {
                await session.stop()
                return
            }
            receiverTransportID = transportID
            state = .connected
        } catch {
            guard currentAttempt == attempt else {
                return
            }
            await session.stop()
            self.session = nil
            state = .failed(Self.message(for: error))
        }
    }

    /// Asks the connected device to load `media`.
    func load(_ media: CastClient.Media) async throws {
        guard state == .connected,
              let transportID = receiverTransportID,
              let session else {
            throw CastClient.ClientError.notConnected
        }
        resumePosition = nil
        try await session.loadMedia(media, transportID: transportID)
    }

    /// Resumes the paused media.
    func play() async {
        guard state == .connected, let session else {
            return
        }
        await session.resumePlayback()
    }

    /// Pauses the playing media.
    func pause() async {
        guard state == .connected, let session else {
            return
        }
        await session.pausePlayback()
    }

    /// Moves the media to `position`, in seconds.
    func seek(to position: TimeInterval) async {
        guard state == .connected, let session else {
            return
        }
        await session.seekPlayback(to: position)
    }

    /// Sets the device volume, from 0 to 1, and keeps showing what the device reports.
    func setVolume(_ level: Double) async {
        guard state == .connected, let session else {
            return
        }
        await session.setVolume(level)
    }

    /// Mutes or unmutes the device, keeping the level the device reports.
    func setMuted(_ muted: Bool) async {
        guard state == .connected, let session else {
            return
        }
        await session.setMuted(muted)
    }

    /// Stops the playing media and keeps the session open.
    func stopPlayback() async {
        guard state == .connected, let session else {
            return
        }
        await session.stopMediaPlayback()
        apply(nil)
    }

    /// Ends the session and returns to the idle state.
    func disconnect() async {
        attempt += 1
        await stopSession()
        connectedDevice = nil
        receiverTransportID = nil
        resumePosition = nil
        mediaStatus = nil
        mediaStatusReceivedAt = nil
        volume = nil
        state = .idle
    }

    private func apply(_ status: CastClient.MediaStatus?) {
        mediaStatus = status
        mediaStatusReceivedAt = status == nil ? nil : Date()
        resumePosition = status == nil ? nil : livePosition
    }

    private func receiverStopped() {
        guard state == .connected else {
            return
        }
        resumePosition = livePosition ?? resumePosition
        receiverTransportID = nil
        mediaStatus = nil
        mediaStatusReceivedAt = nil
        state = .failed("The device stopped the receiver. Connect again to continue.")
        CastLog.connection.error(
            "Receiver stopped by the device at \(self.resumePosition ?? 0, privacy: .public)s"
        )
    }

    /// Reports a transport that died, for example because the Mac slept, and keeps the
    /// position so the cast can be resumed.
    private func connectionLost() {
        guard state == .connected else {
            return
        }
        resumePosition = livePosition ?? resumePosition
        receiverTransportID = nil
        mediaStatus = nil
        mediaStatusReceivedAt = nil
        state = .failed(Self.connectionLostMessage)
        CastLog.connection.error(
            "Connection lost; resume position \(self.resumePosition ?? 0, privacy: .public)s"
        )
    }

    static let connectionLostMessage =
        "The connection to the device was lost. Connect again to continue."

    /// Whether the session ended because its transport died, which is recoverable
    /// without the user doing anything.
    var isConnectionLost: Bool {
        state == .failed(Self.connectionLostMessage)
    }

    private func stopSession() async {
        if let session {
            await session.stop()
        }
        session = nil
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}

extension CastConnectionModel: CastMediaLoading {
    var isConnected: Bool {
        state == .connected
    }
}
