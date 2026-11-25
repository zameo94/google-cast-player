import Foundation
import Network
import Testing
@testable import GoogleCastPlayer

/// Session double that reports what the connection state asks of it.
@MainActor
final class FakeCastSession: CastSessionControlling {
    var result: Result<String, any Error>
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var loadedMedia: [CastClient.Media] = []
    private(set) var stopMediaCount = 0
    private(set) var resumeCount = 0
    private(set) var pauseCount = 0
    private(set) var seekPositions: [TimeInterval] = []
    var onMediaStatusChange: ((CastClient.MediaStatus?) -> Void)?
    var onReceiverStopped: (() -> Void)?
    var onConnectionEnded: (() -> Void)?
    var onVolumeChange: ((CastClient.Volume?) -> Void)?
    private(set) var volumeLevels: [Double] = []
    var loadError: (any Error)?

    init(result: Result<String, any Error> = .success("web-5")) {
        self.result = result
    }

    func start() async throws -> String {
        startCount += 1
        return try result.get()
    }

    func loadMedia(_ media: CastClient.Media, transportID: String) async throws {
        if let loadError {
            throw loadError
        }
        loadedMedia.append(media)
    }

    func resumePlayback() async {
        resumeCount += 1
    }

    func pausePlayback() async {
        pauseCount += 1
    }

    func seekPlayback(to position: TimeInterval) async {
        seekPositions.append(position)
    }

    func stopMediaPlayback() async {
        stopMediaCount += 1
    }

    func setVolume(_ level: Double) async {
        volumeLevels.append(level)
    }

    func stop() async {
        stopCount += 1
    }
}

@MainActor
struct CastConnectionModelTests {
    private func device(withEndpoint: Bool = true) -> CastDevice {
        CastDevice(
            id: "living-room",
            name: "Living Room",
            modelName: "Chromecast",
            endpoint: withEndpoint
                ? .service(name: "Living Room", type: "_googlecast._tcp", domain: "local.", interface: nil)
                : nil
        )
    }

    private func model(
        session: FakeCastSession
    ) -> CastConnectionModel {
        CastConnectionModel(makeSession: { _ in session })
    }

    @Test func startsIdle() {
        let connection = model(session: FakeCastSession())

        #expect(connection.state == .idle)
        #expect(connection.connectedDevice == nil)
        #expect(connection.receiverTransportID == nil)
    }

    @Test func connectsAndKeepsTheReceiver() async {
        let session = FakeCastSession()
        let connection = model(session: session)
        let device = device()

        await connection.connect(to: device)

        #expect(connection.state == .connected)
        #expect(connection.connectedDevice == device)
        #expect(connection.receiverTransportID == "web-5")
        #expect(session.startCount == 1)
    }

    @Test func reportsARejectedConnection() async {
        let failure = CastClient.ClientError.receiverLaunchTimedOut
        let session = FakeCastSession(result: .failure(failure))
        let connection = model(session: session)

        await connection.connect(to: device())

        #expect(connection.state == .failed(failure.errorDescription ?? ""))
        #expect(connection.receiverTransportID == nil)
        #expect(session.stopCount == 1)
    }

    @Test func refusesADeviceWithoutAnEndpoint() async {
        let session = FakeCastSession()
        let connection = model(session: session)

        await connection.connect(to: device(withEndpoint: false))

        #expect(session.startCount == 0)
        guard case let .failed(message) = connection.state else {
            Issue.record("Expected a failure, got \(connection.state)")
            return
        }
        #expect(message.contains("cannot be reached"))
    }

    @Test func connectingAgainToTheSameDeviceKeepsTheSession() async {
        let session = FakeCastSession()
        let connection = model(session: session)
        let device = device()
        await connection.connect(to: device)

        await connection.connect(to: device)

        #expect(session.startCount == 1)
        #expect(session.stopCount == 0)
        #expect(connection.state == .connected)
    }

    @Test func forwardsThePlaybackCommands() async {
        let session = FakeCastSession()
        let connection = model(session: session)
        await connection.connect(to: device())

        await connection.pause()
        await connection.play()
        await connection.seek(to: 42)

        #expect(session.pauseCount == 1)
        #expect(session.resumeCount == 1)
        #expect(session.seekPositions == [42])
    }

    @Test func keepsTheMediaStatusReportedByTheSession() async {
        let session = FakeCastSession()
        let connection = model(session: session)
        await connection.connect(to: device())
        let status = CastClient.MediaStatus(
            mediaSessionID: 7,
            playerState: .playing,
            position: 5,
            duration: 90,
            idleReason: nil
        )

        session.onMediaStatusChange?(status)

        #expect(connection.mediaStatus == status)
        #expect(connection.mediaStatusReceivedAt != nil)
    }

    @Test func mapsTheReportedStatusToAPlaybackSnapshot() async {
        let session = FakeCastSession()
        let connection = model(session: session)
        await connection.connect(to: device())

        session.onMediaStatusChange?(
            CastClient.MediaStatus(mediaSessionID: 7, playerState: .playing, position: 30, duration: 90, idleReason: nil)
        )

        let snapshot = connection.playbackSnapshot
        #expect(snapshot?.status == .playing)
        #expect(snapshot?.position == 30)
        #expect(snapshot?.duration == 90)
        #expect(snapshot?.receivedAt != nil)
    }

    @Test func mapsAnIdleErrorToFailureAndAnIdleStopToFinished() async {
        let session = FakeCastSession()
        let connection = model(session: session)
        await connection.connect(to: device())

        session.onMediaStatusChange?(
            CastClient.MediaStatus(mediaSessionID: 7, playerState: .idle, position: nil, duration: 90, idleReason: "ERROR")
        )
        #expect(connection.playbackSnapshot?.status == .failed)

        session.onMediaStatusChange?(
            CastClient.MediaStatus(mediaSessionID: 7, playerState: .idle, position: nil, duration: 90, idleReason: "CANCELLED")
        )
        #expect(connection.playbackSnapshot?.status == .finished)
    }

    @Test func reportsWhenTheDeviceStopsItsReceiver() async {
        let session = FakeCastSession()
        let connection = model(session: session)
        await connection.connect(to: device())

        session.onReceiverStopped?()

        guard case let .failed(message) = connection.state else {
            Issue.record("Expected a failure, got \(connection.state)")
            return
        }
        #expect(message.contains("stopped the receiver"))
        #expect(connection.receiverTransportID == nil)
    }

    @Test func clearsTheMediaStatusWhenDisconnecting() async {
        let session = FakeCastSession()
        let connection = model(session: session)
        await connection.connect(to: device())
        session.onMediaStatusChange?(
            CastClient.MediaStatus(mediaSessionID: 7, playerState: .playing, position: 5, duration: 90, idleReason: nil)
        )

        await connection.disconnect()

        #expect(connection.mediaStatus == nil)
    }

    @Test func stopsPlaybackWithoutEndingTheSession() async {
        let session = FakeCastSession()
        let connection = model(session: session)
        await connection.connect(to: device())

        await connection.stopPlayback()

        #expect(session.stopMediaCount == 1)
        #expect(session.stopCount == 0)
        #expect(connection.state == .connected)
        #expect(connection.connectedDevice != nil)
    }

    @Test func stopsTheSessionWhenDisconnecting() async {
        let session = FakeCastSession()
        let connection = model(session: session)
        await connection.connect(to: device())

        await connection.disconnect()

        #expect(connection.state == .idle)
        #expect(connection.connectedDevice == nil)
        #expect(session.stopCount == 1)
    }

    @Test func stopsThePreviousSessionBeforeConnectingToAnotherDevice() async {
        let first = FakeCastSession()
        let second = FakeCastSession()
        var sessions = [first, second]
        let connection = CastConnectionModel(makeSession: { _ in sessions.removeFirst() })
        await connection.connect(to: device())
        let otherDevice = CastDevice(
            id: "bedroom",
            name: "Bedroom",
            endpoint: .service(name: "Bedroom", type: "_googlecast._tcp", domain: "local.", interface: nil)
        )

        await connection.connect(to: otherDevice)

        #expect(first.stopCount == 1)
        #expect(second.startCount == 1)
        #expect(connection.state == .connected)
        #expect(connection.receiverTransportID == "web-5")
    }

    // MARK: - Lost connections

    @Test func reportsWhenTheTransportEnds() async {
        let session = FakeCastSession()
        let connection = model(session: session)
        await connection.connect(to: device())

        session.onConnectionEnded?()

        #expect(connection.state == .failed(CastConnectionModel.connectionLostMessage))
        #expect(!connection.isConnected)
        #expect(connection.receiverTransportID == nil)
    }

    @Test func keepsThePositionSoALostCastCanBeResumed() async {
        let session = FakeCastSession()
        let connection = model(session: session)
        await connection.connect(to: device())
        session.onMediaStatusChange?(
            CastClient.MediaStatus(mediaSessionID: 7, playerState: .playing, position: 30, duration: 90, idleReason: nil)
        )

        session.onConnectionEnded?()

        let position = connection.resumePosition ?? 0
        #expect(position >= 30)
        #expect(position <= 90)
        #expect(connection.mediaStatus == nil)
    }

    @Test func forgetsThePositionWhenTheUserDisconnects() async {
        let session = FakeCastSession()
        let connection = model(session: session)
        await connection.connect(to: device())
        session.onMediaStatusChange?(
            CastClient.MediaStatus(mediaSessionID: 7, playerState: .paused, position: 30, duration: 90, idleReason: nil)
        )

        await connection.disconnect()

        #expect(connection.resumePosition == nil)
    }

    @Test func reconnectsWithANewSessionAfterTheTransportDied() async {
        let first = FakeCastSession()
        let second = FakeCastSession()
        var sessions = [first, second]
        let connection = CastConnectionModel(makeSession: { _ in sessions.removeFirst() })
        await connection.connect(to: device())
        first.onConnectionEnded?()

        await connection.reconnect()

        #expect(first.stopCount == 1)
        #expect(second.startCount == 1)
        #expect(connection.state == .connected)
        #expect(connection.connectedDevice?.id == "living-room")
    }

    // MARK: - Volume

    @Test func keepsTheVolumeTheSessionReports() async {
        let session = FakeCastSession()
        let connection = model(session: session)
        await connection.connect(to: device())

        session.onVolumeChange?(CastClient.Volume(level: 0.35, muted: true))

        #expect(connection.volume == DeviceVolume(level: 0.35, muted: true))
    }

    @Test func forwardsAVolumeChange() async {
        let session = FakeCastSession()
        let connection = model(session: session)
        await connection.connect(to: device())

        await connection.setVolume(0.7)

        #expect(session.volumeLevels == [0.7])
    }

    @Test func ignoresAVolumeChangeWithoutASession() async {
        let session = FakeCastSession()
        let connection = model(session: session)

        await connection.setVolume(0.7)

        #expect(session.volumeLevels.isEmpty)
    }

    @Test func forgetsTheVolumeWhenDisconnecting() async {
        let session = FakeCastSession()
        let connection = model(session: session)
        await connection.connect(to: device())
        session.onVolumeChange?(CastClient.Volume(level: 0.4, muted: false))

        await connection.disconnect()

        #expect(connection.volume == nil)
    }

    @Test func reconnectKeepsThePositionOfTheLostCast() async {
        let first = FakeCastSession()
        let second = FakeCastSession()
        var sessions = [first, second]
        let connection = CastConnectionModel(makeSession: { _ in sessions.removeFirst() })
        await connection.connect(to: device())
        first.onMediaStatusChange?(
            CastClient.MediaStatus(mediaSessionID: 7, playerState: .paused, position: 42, duration: 90, idleReason: nil)
        )
        first.onConnectionEnded?()

        await connection.reconnect()

        #expect(connection.resumePosition == 42)
    }
}
