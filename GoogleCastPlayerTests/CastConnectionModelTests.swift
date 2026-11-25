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

    init(result: Result<String, any Error> = .success("web-5")) {
        self.result = result
    }

    func start() async throws -> String {
        startCount += 1
        return try result.get()
    }

    func stop() {
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

    @Test func stopsTheSessionWhenDisconnecting() async {
        let session = FakeCastSession()
        let connection = model(session: session)
        await connection.connect(to: device())

        connection.disconnect()

        #expect(connection.state == .idle)
        #expect(connection.connectedDevice == nil)
        #expect(session.stopCount == 1)
    }

    @Test func stopsThePreviousSessionBeforeConnectingAgain() async {
        let first = FakeCastSession()
        let second = FakeCastSession()
        var sessions = [first, second]
        let connection = CastConnectionModel(makeSession: { _ in sessions.removeFirst() })
        await connection.connect(to: device())

        await connection.connect(to: device())

        #expect(first.stopCount == 1)
        #expect(second.startCount == 1)
        #expect(connection.state == .connected)
        #expect(connection.receiverTransportID == "web-5")
    }
}
