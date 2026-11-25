import Foundation
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
    /// Receiver transport id, kept for the media load of the next phase.
    private(set) var receiverTransportID: String?
    /// Last media status the receiver reported.
    private(set) var mediaStatus: CastClient.MediaStatus?
    /// When `mediaStatus` was received, used to advance the displayed position.
    private(set) var mediaStatusReceivedAt: Date?

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
        if state == .connected, connectedDevice?.id == device.id {
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
        connectedDevice = device
        receiverTransportID = nil
        state = .connecting

        let session = makeSession(endpoint)
        session.onMediaStatusChange = { [weak self] status in
            self?.mediaStatus = status
            self?.mediaStatusReceivedAt = status == nil ? nil : Date()
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

    /// Stops the playing media and keeps the session open.
    func stopPlayback() async {
        guard state == .connected, let session else {
            return
        }
        await session.stopMediaPlayback()
        mediaStatus = nil
        mediaStatusReceivedAt = nil
    }

    /// Ends the session and returns to the idle state.
    func disconnect() async {
        attempt += 1
        await stopSession()
        connectedDevice = nil
        receiverTransportID = nil
        mediaStatus = nil
        mediaStatusReceivedAt = nil
        state = .idle
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
