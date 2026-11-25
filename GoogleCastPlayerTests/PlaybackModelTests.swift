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
    var resumePosition: TimeInterval?
    private(set) var reconnectCount = 0
    /// Whether `reconnect()` restores the connection.
    var reconnects = true

    func load(_ media: CastClient.Media) async throws {
        if let loadError {
            throw loadError
        }
        loadedMedia.append(media)
    }

    func reconnect() async {
        reconnectCount += 1
        isConnected = reconnects
    }
}

/// Wake assertion double that mirrors the real begin/end semantics.
@MainActor
final class FakePowerAssertion: CastPowerAsserting {
    private(set) var beginCount = 0
    private(set) var endCount = 0
    private(set) var isActive = false

    func begin() {
        guard !isActive else {
            return
        }
        beginCount += 1
        isActive = true
    }

    func end() {
        guard isActive else {
            return
        }
        endCount += 1
        isActive = false
    }
}

/// Sleep watcher double the test fires by hand.
@MainActor
final class FakeSleepWatcher: SystemSleepWatching {
    var onWake: (() -> Void)?
    private(set) var startCount = 0

    func start() {
        startCount += 1
    }

    /// Reports a wake the way the workspace notification would.
    func fire() {
        onWake?()
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

    // MARK: - Keeping the Mac awake

    @Test func keepsTheMacAwakeWhileCasting() async throws {
        let power = FakePowerAssertion()
        let model = PlaybackModel(server: try successServer(), power: power)

        await model.play(file: file(), connection: FakeMediaLoader())

        #expect(power.isActive)
        #expect(power.beginCount == 1)
    }

    @Test func releasesTheMacWhenTheCastStops() async throws {
        let power = FakePowerAssertion()
        let model = PlaybackModel(server: try successServer(), power: power)
        await model.play(file: file(), connection: FakeMediaLoader())

        model.stop()

        #expect(!power.isActive)
        #expect(power.endCount == 1)
    }

    @Test func releasesTheMacWhenTheCastCannotStart() async {
        let power = FakePowerAssertion()
        let loader = FakeMediaLoader()
        loader.loadError = CastClient.ClientError.receiverLaunchTimedOut
        let model = PlaybackModel(server: FakeMediaServer(startResult: .failure(
            LocalMediaServer.ServerError.cannotStart("port busy")
        )), power: power)

        await model.play(file: file(), connection: loader)

        #expect(!power.isActive)
    }

    // MARK: - Interrupted casts

    @Test func interruptsTheCastWhenTheConnectionIsLost() async throws {
        let server = try successServer()
        let power = FakePowerAssertion()
        let model = PlaybackModel(server: server, power: power)
        await model.play(file: file(), connection: FakeMediaLoader())

        model.interrupt(reason: "The connection to the device was lost.")

        #expect(model.state == .interrupted(reason: "The connection to the device was lost."))
        #expect(server.stops >= 2)
        #expect(!power.isActive)
        #expect(model.file?.name == "movie.mp4")
    }

    @Test func ignoresAnInterruptionWhenNothingWasCasting() async {
        let model = PlaybackModel(server: FakeMediaServer())

        model.interrupt(reason: "The connection to the device was lost.")

        #expect(model.state == .idle)
        #expect(model.file == nil)
    }

    @Test func resumesTheInterruptedCastAtTheLastPosition() async throws {
        let server = try successServer()
        let loader = FakeMediaLoader()
        let model = PlaybackModel(server: server, power: FakePowerAssertion())
        await model.play(file: file(), connection: loader)
        loader.resumePosition = 63
        model.interrupt(reason: "lost")

        await model.resume()

        #expect(loader.reconnectCount == 1)
        #expect(loader.loadedMedia.count == 2)
        #expect(loader.loadedMedia.last?.currentTime == 63)
        guard case .casting = model.state else {
            Issue.record("Expected casting, got \(model.state)")
            return
        }
        #expect(server.files.map(\.name) == ["movie.mp4", "movie.mp4"])
    }

    @Test func keepsTheCastInterruptedWhenTheDeviceDoesNotAnswerAgain() async throws {
        let loader = FakeMediaLoader()
        loader.reconnects = false
        let model = PlaybackModel(server: try successServer(), power: FakePowerAssertion())
        await model.play(file: file(), connection: loader)
        model.interrupt(reason: "lost")

        await model.resume()

        guard case .interrupted = model.state else {
            Issue.record("Expected an interrupted cast, got \(model.state)")
            return
        }
        #expect(loader.loadedMedia.count == 1)
    }

    // MARK: - Wake

    @Test func startsWatchingForWakeOnce() {
        let watcher = FakeSleepWatcher()
        let model = PlaybackModel(server: FakeMediaServer(), sleepWatcher: watcher)

        model.startWatchingForWake()
        model.startWatchingForWake()

        #expect(watcher.startCount == 1)
        #expect(watcher.onWake != nil)
    }

    @Test func resumesTheInterruptedCastAfterTheMacWakes() async throws {
        let loader = FakeMediaLoader()
        let model = PlaybackModel(server: try successServer(), power: FakePowerAssertion())
        await model.play(file: file(), connection: loader)
        loader.resumePosition = 90
        model.interrupt(reason: "lost")

        await model.handleWake()

        #expect(loader.reconnectCount == 1)
        #expect(loader.loadedMedia.last?.currentTime == 90)
        guard case .casting = model.state else {
            Issue.record("Expected casting, got \(model.state)")
            return
        }
    }

    @Test func retriesTheResumeWhileTheNetworkComesBack() async throws {
        let loader = FakeMediaLoader()
        loader.reconnects = false
        let model = PlaybackModel(
            server: try successServer(),
            power: FakePowerAssertion(),
            sleeper: ImmediateSleeper()
        )
        await model.play(file: file(), connection: loader)
        model.interrupt(reason: "lost")

        await model.handleWake()

        #expect(loader.reconnectCount == 3)
        guard case .interrupted = model.state else {
            Issue.record("Expected an interrupted cast, got \(model.state)")
            return
        }
    }

    @Test func leavesARunningCastAloneWhenTheMacWakes() async throws {
        let server = try successServer()
        let loader = FakeMediaLoader()
        let model = PlaybackModel(server: server, power: FakePowerAssertion())
        await model.play(file: file(), connection: loader)

        await model.handleWake()

        #expect(loader.reconnectCount == 0)
        #expect(server.files.count == 1)
    }
}
