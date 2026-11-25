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
    /// Asks the running receiver to load `media`.
    func loadMedia(_ media: CastClient.Media, transportID: String) async throws
    /// Ends the session: stops the media and the receiver, then closes.
    func stop() async
}

extension CastClient: CastSessionControlling {
    func start() async throws -> String {
        try await connect()
        return try await launchDefaultReceiver()
    }

    func loadMedia(_ media: CastClient.Media, transportID: String) async throws {
        try await load(media, transportID: transportID)
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
    func connect(to device: CastDevice) async {
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

    /// Ends the session and returns to the idle state.
    func disconnect() async {
        attempt += 1
        await stopSession()
        connectedDevice = nil
        receiverTransportID = nil
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
