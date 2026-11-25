import Foundation
import Network
import Security

/// Byte transport to a Cast device.
///
/// A transport carries framed protocol messages; it knows nothing about their meaning.
/// `receive()` returns the next chunk of bytes, or `nil` once the connection is gone.
protocol CastTransporting: Sendable {
    func connect() async throws
    func send(_ data: Data) async throws
    func receive() async -> Data?
    func close()
}

/// Transport to a Cast device over TLS on the port its Bonjour record advertises.
///
/// Cast devices present a self-signed certificate, so the handshake accepts the device
/// certificate instead of requiring a trusted chain; the connection stays on the local
/// network and the protocol authenticates nothing else.
///
/// Mutable state is confined to `queue`, which is also the queue the connection delivers
/// its callbacks on.
final class TLSCastTransport: CastTransporting, @unchecked Sendable {
    private let endpoint: NWEndpoint
    private let queue = DispatchQueue(label: "io.github.zameo94.GoogleCastPlayer.cast-transport")

    // State below is confined to `queue`.
    private var connection: NWConnection?
    private var pendingChunks: [Data] = []
    private var waiting: CheckedContinuation<Data?, Never>?
    private var isClosed = false

    init(endpoint: NWEndpoint) {
        self.endpoint = endpoint
    }

    func connect() async throws {
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_verify_block(
            tlsOptions.securityProtocolOptions,
            { _, _, complete in complete(true) },
            queue
        )
        let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        let connection = NWConnection(to: endpoint, using: parameters)

        let attempt = ConnectionAttempt()
        try await withCheckedThrowingContinuation { continuation in
            attempt.continuation = continuation
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    attempt.finish(.success(()))
                case let .failed(error):
                    attempt.finish(.failure(error))
                case let .waiting(error):
                    attempt.finish(.failure(error))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }

        queue.async {
            self.connection = connection
            self.startReceiving()
        }
    }

    func send(_ data: Data) async throws {
        guard let connection else {
            throw TransportError.notConnected
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func receive() async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async {
                if !self.pendingChunks.isEmpty {
                    continuation.resume(returning: self.pendingChunks.removeFirst())
                } else if self.isClosed {
                    continuation.resume(returning: nil)
                } else {
                    self.waiting = continuation
                }
            }
        }
    }

    func close() {
        queue.async {
            self.isClosed = true
            self.connection?.cancel()
            self.connection = nil
            self.pendingChunks.removeAll()
            self.waiting?.resume(returning: nil)
            self.waiting = nil
        }
    }

    private func startReceiving() {
        guard let connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            if let chunk, !chunk.isEmpty {
                if let waiting = self.waiting {
                    self.waiting = nil
                    waiting.resume(returning: chunk)
                } else {
                    self.pendingChunks.append(chunk)
                }
            }
            if error != nil || isComplete {
                self.isClosed = true
                self.waiting?.resume(returning: nil)
                self.waiting = nil
                return
            }
            self.startReceiving()
        }
    }

    enum TransportError: Error, Equatable {
        case notConnected
    }
}

/// Resumes a connection attempt exactly once.
private final class ConnectionAttempt: @unchecked Sendable {
    var continuation: CheckedContinuation<Void, any Error>?
    private var finished = false

    func finish(_ result: Result<Void, any Error>) {
        guard !finished, let continuation else {
            return
        }
        finished = true
        self.continuation = nil
        continuation.resume(with: result)
    }
}
