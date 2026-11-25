import Foundation
import Testing
@testable import GoogleCastPlayer

/// Server double that records the file it was asked to serve.
final class FakeMediaServer: MediaServing, @unchecked Sendable {
    private let lock = NSLock()
    private var servedFiles: [MediaFile] = []
    private var stopCount = 0
    var startResult: Result<URL, any Error>?

    init(startResult: Result<URL, any Error>? = nil) {
        self.startResult = startResult
    }

    var files: [MediaFile] { lock.withLock { servedFiles } }
    var stops: Int { lock.withLock { stopCount } }

    func startServing(_ file: MediaFile) async throws -> URL {
        lock.withLock { servedFiles.append(file) }
        guard let startResult else {
            throw LocalMediaServer.ServerError.cannotStart("no result configured")
        }
        return try startResult.get()
    }

    func stopServing() {
        lock.withLock { stopCount += 1 }
    }
}

/// Loader double standing in for a connected session.
@MainActor
final class FakeMediaLoader: CastMediaLoading {
    var isConnected = true
    var loadError: (any Error)?
    private(set) var loadedMedia: [CastClient.Media] = []

    func load(_ media: CastClient.Media) async throws {
        if let loadError {
            throw loadError
        }
        loadedMedia.append(media)
    }
}

@MainActor
struct PlaybackModelTests {
    private func successServer() throws -> FakeMediaServer {
        let url = try #require(URL(string: "http://192.168.1.40:5000/media/abc"))
        return FakeMediaServer(startResult: .success(url))
    }

    private func file(named name: String = "movie.mp4") -> MediaFile {
        MediaFile(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            byteCount: 1024,
            format: MediaFormat(fileExtension: (name as NSString).pathExtension.lowercased())
        )
    }

    @Test func refusesToCastWithoutAConnection() async {
        let model = PlaybackModel(server: FakeMediaServer())
        let loader = FakeMediaLoader()
        loader.isConnected = false

        await model.play(file: file(), connection: loader)

        guard case let .failed(message) = model.state else {
            Issue.record("Expected a failure, got \(model.state)")
            return
        }
        #expect(message.contains("Connect"))
    }

    @Test func servesTheFileAndAsksTheDeviceToLoadIt() async throws {
        let server = try successServer()
        let loader = FakeMediaLoader()
        let model = PlaybackModel(server: server)
        let mediaFile = file()

        await model.play(file: mediaFile, connection: loader)

        guard case let .casting(url) = model.state else {
            Issue.record("Expected casting, got \(model.state)")
            return
        }
        #expect(url.absoluteString == "http://192.168.1.40:5000/media/abc")
        #expect(server.files.map(\.name) == ["movie.mp4"])
        #expect(loader.loadedMedia.count == 1)
        let loaded = try #require(loader.loadedMedia.first)
        #expect(loaded.contentURL == url)
        #expect(loaded.contentType == "video/mp4")
        #expect(loaded.streamType == "BUFFERED")
        #expect(loaded.title == "movie.mp4")
    }

    @Test func stopsServingWhenTheLoadFails() async throws {
        let server = try successServer()
        let loader = FakeMediaLoader()
        loader.loadError = CastClient.ClientError.receiverLaunchTimedOut
        let model = PlaybackModel(server: server)

        await model.play(file: file(), connection: loader)

        guard case let .failed(message) = model.state else {
            Issue.record("Expected a failure, got \(model.state)")
            return
        }
        #expect(message == CastClient.ClientError.receiverLaunchTimedOut.errorDescription)
        #expect(server.stops >= 1)
        #expect(loader.loadedMedia.isEmpty)
    }

    @Test func stopsServingWhenTheServerFails() async {
        let failure = LocalMediaServer.ServerError.fileNotReadable("movie.mp4")
        let server = FakeMediaServer(startResult: .failure(failure))
        let loader = FakeMediaLoader()
        let model = PlaybackModel(server: server)

        await model.play(file: file(), connection: loader)

        guard case let .failed(message) = model.state else {
            Issue.record("Expected a failure, got \(model.state)")
            return
        }
        #expect(message == failure.errorDescription)
        #expect(server.stops >= 1)
        #expect(loader.loadedMedia.isEmpty)
    }

    @Test func stoppingReleasesTheServer() async throws {
        let server = try successServer()
        let model = PlaybackModel(server: server)
        await model.play(file: file(), connection: FakeMediaLoader())

        model.stop()

        #expect(model.state == .idle)
        #expect(server.stops >= 2)
    }

    @Test func stoppingPlaybackKeepsTheSessionOpen() async throws {
        let session = FakeCastSession()
        let connection = CastConnectionModel(makeSession: { _ in session })
        let device = CastDevice(
            id: "living-room",
            name: "Living Room",
            endpoint: .service(name: "Living Room", type: "_googlecast._tcp", domain: "local.", interface: nil)
        )
        await connection.connect(to: device)
        let server = try successServer()
        let model = PlaybackModel(server: server)
        await model.play(file: file(), connection: connection)

        await model.stopPlayback(connection: connection)

        #expect(model.state == .idle)
        #expect(connection.state == .connected)
        #expect(session.stopMediaCount == 1)
        #expect(session.stopCount == 0)
        #expect(server.stops >= 2)
    }

    @Test func servesTheUrlItHandsToTheDevice() async throws {
        let contents = Data(repeating: 0x11, count: 2048)
        let url = try TestFixture.file(named: "movie.mp4", contents: contents)
        defer { TestFixture.remove(url) }
        let mediaFile = MediaFile(
            url: url,
            name: "movie.mp4",
            byteCount: Int64(contents.count),
            format: MediaFormat(fileExtension: "mp4")
        )
        let loader = FakeMediaLoader()
        let model = PlaybackModel()
        defer { model.stop() }

        await model.play(file: mediaFile, connection: loader)

        let loaded = try #require(loader.loadedMedia.first)
        let (data, response) = try await URLSession.shared.data(from: loaded.contentURL)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(data == contents)
    }

    @Test func mapsTheFileTypeToAMediaType() {
        #expect(PlaybackModel.contentType(for: file(named: "clip.mp4")) == "video/mp4")
        #expect(PlaybackModel.contentType(for: file(named: "clip.mov")) == "video/quicktime")
        #expect(PlaybackModel.contentType(for: file(named: "clip.unknown")) == "video/mp4")
    }
}
