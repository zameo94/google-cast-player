import Foundation
import Network
import Testing
@testable import GoogleCastPlayer

struct LocalMediaServerTests {
    private static let contents = Data((0..<1000).map { UInt8($0 % 251) })

    // MARK: - Happy path

    @Test func servesTheWholeFile() async throws {
        try await withServer { _, endpoint in
            let (response, data) = try await get(endpoint.url)

            #expect(response.statusCode == 200)
            #expect(response.value(forHTTPHeaderField: "Content-Length") == "1000")
            #expect(response.value(forHTTPHeaderField: "Content-Type") == "video/mp4")
            #expect(response.value(forHTTPHeaderField: "Accept-Ranges") == "bytes")
            #expect(data == Self.contents)
        }
    }

    @Test func answersHeadWithoutABody() async throws {
        try await withServer { _, endpoint in
            let (response, data) = try await get(endpoint.url, method: "HEAD")

            #expect(response.statusCode == 200)
            #expect(response.value(forHTTPHeaderField: "Content-Length") == "1000")
            #expect(data.isEmpty)
        }
    }

    // MARK: - Ranges

    @Test func servesAClosedRange() async throws {
        try await withServer { _, endpoint in
            let (response, data) = try await get(endpoint.url, headers: ["Range": "bytes=10-19"])

            #expect(response.statusCode == 206)
            #expect(response.value(forHTTPHeaderField: "Content-Range") == "bytes 10-19/1000")
            #expect(response.value(forHTTPHeaderField: "Content-Length") == "10")
            #expect(data == Self.contents.subdata(in: 10..<20))
        }
    }

    @Test func servesAnOpenEndedRange() async throws {
        try await withServer { _, endpoint in
            let (response, data) = try await get(endpoint.url, headers: ["Range": "bytes=990-"])

            #expect(response.statusCode == 206)
            #expect(response.value(forHTTPHeaderField: "Content-Range") == "bytes 990-999/1000")
            #expect(data == Self.contents.subdata(in: 990..<1000))
        }
    }

    @Test func servesASuffixRange() async throws {
        try await withServer { _, endpoint in
            let (response, data) = try await get(endpoint.url, headers: ["Range": "bytes=-10"])

            #expect(response.statusCode == 206)
            #expect(response.value(forHTTPHeaderField: "Content-Range") == "bytes 990-999/1000")
            #expect(data == Self.contents.subdata(in: 990..<1000))
        }
    }

    @Test func answersHeadForARangeWithoutABody() async throws {
        try await withServer { _, endpoint in
            let (response, data) = try await get(endpoint.url, method: "HEAD", headers: ["Range": "bytes=0-4"])

            #expect(response.statusCode == 206)
            #expect(response.value(forHTTPHeaderField: "Content-Range") == "bytes 0-4/1000")
            #expect(data.isEmpty)
        }
    }

    @Test func reportsAnUnsatisfiableRange() async throws {
        try await withServer { _, endpoint in
            let (response, data) = try await get(endpoint.url, headers: ["Range": "bytes=2000-"])

            #expect(response.statusCode == 416)
            #expect(response.value(forHTTPHeaderField: "Content-Range") == "bytes */1000")
            #expect(data.isEmpty)
        }
    }

    @Test func ignoresARangeItCannotParse() async throws {
        try await withServer { _, endpoint in
            let (response, data) = try await get(endpoint.url, headers: ["Range": "bytes=abc"])

            #expect(response.statusCode == 200)
            #expect(data == Self.contents)
        }
    }

    // MARK: - Access restrictions

    @Test func refusesEveryPathButTheSelectedFile() async throws {
        try await withServer { _, endpoint in
            let host = try #require(endpoint.url.host)
            let root = try #require(URL(string: "http://\(host):\(endpoint.port)/"))
            let (rootResponse, _) = try await get(root)
            #expect(rootResponse.statusCode == 404)

            let wrongToken = try #require(URL(string: "http://\(host):\(endpoint.port)/media/guess"))
            let (wrongResponse, _) = try await get(wrongToken)
            #expect(wrongResponse.statusCode == 404)
        }
    }

    @Test func refusesAPathWithTraversalSegments() async throws {
        try await withServer { _, endpoint in
            let host = try #require(endpoint.url.host)
            let payload = Data("GET /media/../etc/passwd HTTP/1.1\r\nHost: \(host)\r\n\r\n".utf8)

            let response = try await rawExchange(payload, port: endpoint.port)

            #expect(String(decoding: response, as: UTF8.self).hasPrefix("HTTP/1.1 404"))
        }
    }

    @Test func refusesUnsupportedMethods() async throws {
        try await withServer { _, endpoint in
            let (response, _) = try await get(endpoint.url, method: "POST")

            #expect(response.statusCode == 405)
            #expect(response.value(forHTTPHeaderField: "Allow") == "GET, HEAD")
        }
    }

    @Test func answersMalformedRequestsSafely() async throws {
        try await withServer { _, endpoint in
            let response = try await rawExchange(Data("not a request\r\n\r\n".utf8), port: endpoint.port)

            #expect(String(decoding: response, as: UTF8.self).hasPrefix("HTTP/1.1 400"))
        }
    }

    // MARK: - Lifecycle

    @Test func replacesTheServedFileWhenStartedAgain() async throws {
        let firstContents = Data("first file".utf8)
        let firstURL = try TestFixture.file(named: "first.mp4", contents: firstContents)
        let secondContents = Data("second file".utf8)
        let secondURL = try TestFixture.file(named: "second.mp4", contents: secondContents)
        defer {
            TestFixture.remove(firstURL)
            TestFixture.remove(secondURL)
        }

        let server = LocalMediaServer()
        defer { server.stop() }
        let firstEndpoint = try await server.start(file: mediaFile(at: firstURL), host: "127.0.0.1")
        let secondEndpoint = try await server.start(file: mediaFile(at: secondURL), host: "127.0.0.1")

        // A new start opens a new listener, so the previous endpoint stops answering.
        await #expect(throws: (any Error).self) {
            _ = try await URLSession.shared.data(for: URLRequest(url: firstEndpoint.url))
        }

        let (newResponse, data) = try await get(secondEndpoint.url)
        #expect(newResponse.statusCode == 200)
        #expect(data == secondContents)
    }

    @Test func stopsServingAfterStop() async throws {
        let url = try TestFixture.file(named: "movie.mp4", contents: Self.contents)
        defer { TestFixture.remove(url) }
        let server = LocalMediaServer()
        let endpoint = try await server.start(file: mediaFile(at: url), host: "127.0.0.1")

        server.stop()

        await #expect(throws: (any Error).self) {
            _ = try await URLSession.shared.data(for: URLRequest(url: endpoint.url))
        }
    }

    @Test func refusesToStartForAFileThatCannotBeRead() async throws {
        let missingURL = TestFixture.missingFileURL(named: "missing.mp4")
        let server = LocalMediaServer()
        defer { server.stop() }

        await #expect(throws: LocalMediaServer.ServerError.fileNotReadable("missing.mp4")) {
            _ = try await server.start(file: mediaFile(at: missingURL), host: "127.0.0.1")
        }
    }

    // MARK: - Helpers

    private func withServer(
        _ body: (LocalMediaServer, LocalMediaServer.Endpoint) async throws -> Void
    ) async throws {
        let url = try TestFixture.file(named: "movie.mp4", contents: Self.contents)
        let server = LocalMediaServer()
        defer {
            server.stop()
            TestFixture.remove(url)
        }
        let endpoint = try await server.start(file: mediaFile(at: url), host: "127.0.0.1")
        try await body(server, endpoint)
    }

    private func mediaFile(at url: URL) -> MediaFile {
        MediaFile(
            url: url,
            name: url.lastPathComponent,
            byteCount: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0),
            format: MediaFormat(fileExtension: url.pathExtension.lowercased())
        )
    }

    private func get(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:]
    ) async throws -> (HTTPURLResponse, Data) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)
        return (httpResponse, data)
    }

    private func rawExchange(_ request: Data, port: UInt16) async throws -> Data {
        let host = try #require(IPv4Address("127.0.0.1"))
        let endpointPort = try #require(NWEndpoint.Port(rawValue: port))
        let connection = NWConnection(host: .ipv4(host), port: endpointPort, using: .tcp)
        let exchange = RawExchange()
        return try await withCheckedThrowingContinuation { continuation in
            exchange.continuation = continuation
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: request, completion: .contentProcessed { error in
                        if let error {
                            exchange.finish(.failure(error))
                            return
                        }
                        exchange.receive(from: connection)
                    })
                case let .failed(error):
                    exchange.finish(.failure(error))
                default:
                    break
                }
            }
            connection.start(queue: exchange.queue)
        }
    }
}

/// Collects a raw TCP answer for the malformed-request tests.
private final class RawExchange: @unchecked Sendable {
    let queue = DispatchQueue(label: "io.github.zameo94.GoogleCastPlayer.tests.raw-exchange")
    var continuation: CheckedContinuation<Data, any Error>?
    private var buffer = Data()
    private var finished = false

    func receive(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [self] data, _, isComplete, error in
            if let data {
                buffer.append(data)
            }
            if let error {
                finish(.failure(error))
                connection.cancel()
                return
            }
            if isComplete {
                finish(.success(buffer))
                connection.cancel()
                return
            }
            receive(from: connection)
        }
    }

    func finish(_ result: Result<Data, any Error>) {
        guard !finished, let continuation else {
            return
        }
        finished = true
        self.continuation = nil
        continuation.resume(with: result)
    }
}
