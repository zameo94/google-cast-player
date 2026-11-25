import Foundation
import Network
import UniformTypeIdentifiers

/// Serves exactly one media file over HTTP for the duration of a cast session.
///
/// The server exposes a single unguessable path and answers 404 for everything else,
/// so the Mac's file system is never reachable and no other resource can be read.
/// It supports GET and HEAD, answers byte-range requests with 206, and closes each
/// connection after one response.
///
/// Every piece of mutable state lives on one serial queue, which is also the queue the
/// listener and its connections deliver callbacks on. `stop()` must therefore never be
/// called from a server callback; callers start and stop it from their own context.
final class LocalMediaServer: @unchecked Sendable {
    enum ServerError: Error, Equatable, LocalizedError {
        /// The listener could not be created or started.
        case cannotStart(String)
        /// The file cannot be read.
        case fileNotReadable(String)

        var errorDescription: String? {
            switch self {
            case let .cannotStart(reason):
                return "The local server could not start: \(reason)"
            case let .fileNotReadable(name):
                return "\u{201C}\(name)\u{201D} cannot be read, so it cannot be served."
            }
        }
    }

    /// Where a receiver can fetch the served file.
    struct Endpoint: Equatable, Sendable {
        let url: URL
        let port: UInt16
    }

    private static let maximumRequestBytes = 16 * 1024
    private static let maximumConnections = 8
    private static let chunkSize = 64 * 1024

    private let queue = DispatchQueue(label: "io.github.zameo94.GoogleCastPlayer.media-server")
    // The properties below are confined to `queue`.
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var fileURL: URL?
    private var token = ""
    private var contentType = "application/octet-stream"

    /// Starts serving `file` and returns the URL a receiver can use.
    ///
    /// - Parameters:
    ///   - file: The only resource the server will serve.
    ///   - host: Address placed in the returned URL. Defaults to the primary local
    ///     network address, falling back to the loopback address.
    func start(file: MediaFile, host: String? = nil) async throws -> Endpoint {
        guard FileManager.default.isReadableFile(atPath: file.url.path(percentEncoded: false)) else {
            throw ServerError.fileNotReadable(file.name)
        }

        let resolvedHost = host ?? LocalNetworkAddress.primaryIPv4() ?? "127.0.0.1"
        let newToken = UUID().uuidString.lowercased()
        let newContentType = UTType(filenameExtension: file.format.fileExtension ?? "")?.preferredMIMEType
            ?? "application/octet-stream"

        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: ServerError.cannotStart("server released"))
                    return
                }
                self.stopLocked()

                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true
                let listener: NWListener
                do {
                    listener = try NWListener(using: parameters, on: .any)
                } catch {
                    continuation.resume(throwing: ServerError.cannotStart(error.localizedDescription))
                    return
                }

                let startGuard = StartGuard()
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                listener.stateUpdateHandler = { [weak self] state in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        guard !startGuard.hasResumed, let port = listener.port?.rawValue else {
                            return
                        }
                        startGuard.hasResumed = true
                        self.listener = listener
                        self.fileURL = file.url
                        self.token = newToken
                        self.contentType = newContentType
                        guard let url = Self.makeURL(host: resolvedHost, port: port, token: newToken) else {
                            self.stopLocked()
                            continuation.resume(throwing: ServerError.cannotStart("invalid endpoint"))
                            return
                        }
                        continuation.resume(returning: Endpoint(url: url, port: port))
                    case let .failed(error):
                        if startGuard.hasResumed {
                            self.stopLocked()
                        } else {
                            startGuard.hasResumed = true
                            listener.cancel()
                            continuation.resume(throwing: ServerError.cannotStart(error.localizedDescription))
                        }
                    default:
                        break
                    }
                }
                listener.start(queue: self.queue)
            }
        }
    }

    /// Stops the server and closes every open connection.
    func stop() {
        queue.sync {
            stopLocked()
        }
    }

    // MARK: - Connections

    private func stopLocked() {
        listener?.cancel()
        listener = nil
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
        fileURL = nil
        token = ""
    }

    private func accept(_ connection: NWConnection) {
        guard fileURL != nil, connections.count < Self.maximumConnections else {
            connection.cancel()
            return
        }

        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.connections[key] = nil
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] chunk, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                return
            }

            var buffer = buffer
            if let chunk {
                buffer.append(chunk)
            }
            if buffer.count > Self.maximumRequestBytes {
                sendStatus(413, reason: "Content Too Large", on: connection)
                return
            }
            if HTTPRequest.isHeadComplete(buffer) {
                guard let request = HTTPRequest.parse(buffer) else {
                    sendStatus(400, reason: "Bad Request", on: connection)
                    return
                }
                respond(to: request, on: connection)
                return
            }
            if isComplete {
                connection.cancel()
                return
            }
            receiveRequest(on: connection, buffer: buffer)
        }
    }

    // MARK: - Responses

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        guard let fileURL else {
            connection.cancel()
            return
        }
        guard request.method == "GET" || request.method == "HEAD" else {
            sendStatus(405, reason: "Method Not Allowed", extraHeaders: ["Allow": "GET, HEAD"], on: connection)
            return
        }
        guard request.path == "/media/\(token)" else {
            sendStatus(404, reason: "Not Found", on: connection)
            return
        }
        guard let size = fileSize(of: fileURL) else {
            sendStatus(500, reason: "Internal Server Error", on: connection)
            return
        }

        let sendsBody = request.method == "GET"
        switch HTTPByteRange.resolve(header: request.headers["range"], size: size) {
        case .complete:
            send(
                status: 200,
                reason: "OK",
                headers: [
                    "Content-Type": contentType,
                    "Content-Length": "\(size)",
                    "Accept-Ranges": "bytes",
                ],
                body: sendsBody ? .file(offset: 0, length: size) : .none,
                on: connection
            )
        case let .partial(range):
            send(
                status: 206,
                reason: "Partial Content",
                headers: [
                    "Content-Type": contentType,
                    "Content-Length": "\(range.length)",
                    "Content-Range": "bytes \(range.start)-\(range.end)/\(size)",
                    "Accept-Ranges": "bytes",
                ],
                body: sendsBody ? .file(offset: range.start, length: range.length) : .none,
                on: connection
            )
        case .unsatisfiable:
            send(
                status: 416,
                reason: "Range Not Satisfiable",
                headers: ["Content-Range": "bytes */\(size)", "Content-Length": "0"],
                body: .none,
                on: connection
            )
        }
    }

    private enum Body {
        case none
        case file(offset: Int64, length: Int64)
    }

    private func sendStatus(
        _ status: Int,
        reason: String,
        extraHeaders: [String: String] = [:],
        on connection: NWConnection
    ) {
        var headers = extraHeaders
        headers["Content-Length"] = "0"
        send(status: status, reason: reason, headers: headers, body: .none, on: connection)
    }

    private func send(
        status: Int,
        reason: String,
        headers: [String: String],
        body: Body,
        on connection: NWConnection
    ) {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        head += "Connection: close\r\n\r\n"

        connection.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            switch body {
            case .none:
                connection.cancel()
            case let .file(offset, length):
                self.sendFile(offset: offset, remaining: length, on: connection)
            }
        })
    }

    private func sendFile(offset: Int64, remaining: Int64, on connection: NWConnection) {
        guard remaining > 0, let fileURL, let handle = try? FileHandle(forReadingFrom: fileURL) else {
            connection.cancel()
            return
        }
        do {
            try handle.seek(toOffset: UInt64(offset))
        } catch {
            try? handle.close()
            connection.cancel()
            return
        }
        streamChunk(from: handle, remaining: remaining, on: connection)
    }

    private func streamChunk(from handle: FileHandle, remaining: Int64, on connection: NWConnection) {
        guard remaining > 0 else {
            try? handle.close()
            connection.cancel()
            return
        }
        let requested = Int(min(remaining, Int64(Self.chunkSize)))
        guard let chunk = try? handle.read(upToCount: requested), !chunk.isEmpty else {
            try? handle.close()
            connection.cancel()
            return
        }

        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else {
                try? handle.close()
                connection.cancel()
                return
            }
            self.streamChunk(from: handle, remaining: remaining - Int64(chunk.count), on: connection)
        })
    }

    // MARK: - Helpers

    private func fileSize(of url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return nil
        }
        return Int64(size)
    }

    private static func makeURL(host: String, port: UInt16, token: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        components.path = "/media/\(token)"
        return components.url
    }
}

/// Start bookkeeping shared by the listener callbacks, which all run on the server queue.
private final class StartGuard: @unchecked Sendable {
    var hasResumed = false
}
