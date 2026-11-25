import Foundation
import Testing
@testable import GoogleCastPlayer

/// Sleeper that returns at once, so a timeout fires without waiting on wall time.
struct ImmediateSleeper: Sleeping {
    func sleep(for duration: Duration) async {}
}

/// Transport double that records what the client sends and delivers what the test pushes.
final class ScriptedCastTransport: CastTransporting, @unchecked Sendable {
    private struct Waiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var sentStorage: [Data] = []
    private var waiters: [Waiter] = []
    private var closed = false
    private var iterator: AsyncStream<Data>.AsyncIterator
    private let continuation: AsyncStream<Data>.Continuation

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        self.iterator = stream.makeAsyncIterator()
        self.continuation = continuation
    }

    var sentFrames: [Data] {
        lock.withLock { sentStorage }
    }

    var sentMessages: [CastMessage] {
        sentFrames.compactMap { frame in
            CastMessage.frames(in: frame).messages.first
        }
    }

    func connect() async throws {}

    func send(_ data: Data) async throws {
        lock.withLock {
            sentStorage.append(data)
            var remaining: [Waiter] = []
            for waiter in waiters {
                if sentStorage.count >= waiter.count {
                    waiter.continuation.resume()
                } else {
                    remaining.append(waiter)
                }
            }
            waiters = remaining
        }
    }

    /// Suspends until the client has sent at least `count` frames.
    func waitForSentFrames(_ count: Int) async {
        let alreadySent = lock.withLock { () -> Bool in
            if sentStorage.count >= count {
                return true
            }
            return false
        }
        if alreadySent {
            return
        }
        await withCheckedContinuation { continuation in
            let satisfied = lock.withLock { () -> Bool in
                if sentStorage.count >= count {
                    return true
                }
                waiters.append(Waiter(count: count, continuation: continuation))
                return false
            }
            if satisfied {
                continuation.resume()
            }
        }
    }

    func receive() async -> Data? {
        await iterator.next()
    }

    var isClosed: Bool {
        lock.withLock { closed }
    }

    func close() {
        lock.withLock { closed = true }
        continuation.finish()
    }

    func push(_ message: CastMessage) {
        continuation.yield(message.framed())
    }
}

@MainActor
struct CastClientTests {
    private func connectClient(
        launchTimeout: Duration = .seconds(1),
        heartbeat: Duration = .seconds(60),
        sleeper: (any Sleeping)? = nil
    ) async throws -> (CastClient, ScriptedCastTransport) {
        let transport = ScriptedCastTransport()
        let client = CastClient(
            transport: transport,
            launchTimeout: launchTimeout,
            heartbeatInterval: heartbeat,
            sleeper: sleeper ?? TaskSleeper()
        )
        try await client.connect()
        return (client, transport)
    }

    @Test func announcesTheSenderWhenConnecting() async throws {
        let (_, transport) = try await connectClient()

        let message = try #require(transport.sentMessages.first)
        #expect(message.sourceID == CastClient.senderID)
        #expect(message.destinationID == CastClient.receiverID)
        #expect(message.namespace == CastClient.Namespace.connection)
        #expect(message.payloadType == .string)
        #expect(message.payload == #"{"type":"CONNECT"}"#)
    }

    @Test func launchesTheDefaultReceiver() async throws {
        let (client, transport) = try await connectClient()

        let launch = Task { try await client.launchDefaultReceiver() }
        await transport.waitForSentFrames(2)

        let request = try #require(transport.sentMessages.last)
        #expect(request.namespace == CastClient.Namespace.receiver)
        #expect(request.payload.contains(#""type":"LAUNCH""#))
        #expect(request.payload.contains("CC1AD845"))

        transport.push(
            CastMessage(
                sourceID: CastClient.receiverID,
                destinationID: CastClient.senderID,
                namespace: CastClient.Namespace.receiver,
                payload: #"{"type":"RECEIVER_STATUS","status":{"applications":[{"appId":"CC1AD845","transportId":"web-5"}]}}"#
            )
        )

        let transportID = try await launch.value
        #expect(transportID == "web-5")
    }

    @Test func ignoresAReceiverStatusForAnotherApplication() async throws {
        let (client, transport) = try await connectClient(launchTimeout: .seconds(30))
        let launch = Task { try await client.launchDefaultReceiver() }
        await transport.waitForSentFrames(2)

        transport.push(
            CastMessage(
                sourceID: CastClient.receiverID,
                destinationID: CastClient.senderID,
                namespace: CastClient.Namespace.receiver,
                payload: #"{"type":"RECEIVER_STATUS","status":{"applications":[{"appId":"OTHER","transportId":"web-9"}]}}"#
            )
        )
        transport.push(
            CastMessage(
                sourceID: CastClient.receiverID,
                destinationID: CastClient.senderID,
                namespace: CastClient.Namespace.receiver,
                payload: #"{"type":"RECEIVER_STATUS","status":{"applications":[{"appId":"CC1AD845","transportId":"web-5"}]}}"#
            )
        )

        let transportID = try await launch.value
        #expect(transportID == "web-5")
    }

    @Test func reportsATimedOutLaunch() async throws {
        let (client, _) = try await connectClient(
            launchTimeout: .seconds(1),
            sleeper: ImmediateSleeper()
        )

        await #expect(throws: CastClient.ClientError.receiverLaunchTimedOut) {
            try await client.launchDefaultReceiver()
        }
    }

    @Test func connectsToTheReceiverAndLoadsTheMedia() async throws {
        let (client, transport) = try await connectClient()
        let url = try #require(URL(string: "http://192.168.1.40:5000/media/abc"))
        let media = CastClient.Media(contentURL: url, contentType: "video/mp4", title: "Holiday Clip")

        let requestID = try await client.load(media, transportID: "web-5")

        let sent = transport.sentMessages
        #expect(sent.count == 3)
        #expect(sent[1].destinationID == "web-5")
        #expect(sent[1].namespace == CastClient.Namespace.connection)
        #expect(sent[1].payload == #"{"type":"CONNECT"}"#)

        let loadMessage = sent[2]
        #expect(loadMessage.destinationID == "web-5")
        #expect(loadMessage.namespace == CastClient.Namespace.media)

        let payload = try #require(
            try JSONSerialization.jsonObject(with: Data(loadMessage.payload.utf8)) as? [String: Any]
        )
        #expect(payload["type"] as? String == "LOAD")
        #expect(payload["requestId"] as? Int == requestID)
        #expect(payload["autoplay"] as? Bool == true)
        let mediaObject = try #require(payload["media"] as? [String: Any])
        #expect(mediaObject["contentId"] as? String == url.absoluteString)
        #expect(mediaObject["contentType"] as? String == "video/mp4")
        #expect(mediaObject["streamType"] as? String == "BUFFERED")
        let metadata = try #require(mediaObject["metadata"] as? [String: Any])
        #expect(metadata["title"] as? String == "Holiday Clip")
    }

    @Test func stopsTheMediaAndTheReceiverBeforeClosing() async throws {
        let (client, transport) = try await connectClient()
        let launch = Task { try await client.launchDefaultReceiver() }
        await transport.waitForSentFrames(2)
        transport.push(
            CastMessage(
                sourceID: CastClient.receiverID,
                destinationID: CastClient.senderID,
                namespace: CastClient.Namespace.receiver,
                payload: #"{"type":"RECEIVER_STATUS","status":{"applications":[{"appId":"CC1AD845","transportId":"web-5","sessionId":"session-1"}]}}"#
            )
        )
        _ = try await launch.value

        client.handle(
            CastMessage(
                sourceID: "web-5",
                destinationID: CastClient.senderID,
                namespace: CastClient.Namespace.media,
                payload: #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":7,"playerState":"PLAYING"}]}"#
            ).framed()
        )
        await client.endSession()

        let sent = transport.sentMessages
        let stopMedia = try #require(sent.first { $0.namespace == CastClient.Namespace.media })
        #expect(stopMedia.destinationID == "web-5")
        #expect(stopMedia.payload.contains(#""type":"STOP""#))
        #expect(stopMedia.payload.contains(#""mediaSessionId":7"#))
        #expect(stopMedia.payload.contains(#""requestId""#))

        let stopReceiver = try #require(sent.last { $0.namespace == CastClient.Namespace.receiver })
        #expect(stopReceiver.destinationID == CastClient.receiverID)
        #expect(stopReceiver.payload.contains("session-1"))
        #expect(stopReceiver.payload.contains(#""requestId""#))

        let close = try #require(sent.last { $0.namespace == CastClient.Namespace.connection })
        #expect(close.payload == #"{"type":"CLOSE"}"#)
        #expect(transport.isClosed)
    }

    private func connectAndReportMedia(
        _ client: CastClient,
        _ transport: ScriptedCastTransport,
        state: String = "PLAYING"
    ) async throws {
        let launch = Task { try await client.launchDefaultReceiver() }
        await transport.waitForSentFrames(2)
        transport.push(
            CastMessage(
                sourceID: CastClient.receiverID,
                destinationID: CastClient.senderID,
                namespace: CastClient.Namespace.receiver,
                payload: #"{"type":"RECEIVER_STATUS","status":{"applications":[{"appId":"CC1AD845","transportId":"web-5","sessionId":"session-1"}]}}"#
            )
        )
        _ = try await launch.value
        client.handle(
            CastMessage(
                sourceID: "web-5",
                destinationID: CastClient.senderID,
                namespace: CastClient.Namespace.media,
                payload: #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":7,"playerState":"\#(state)","currentTime":5.5,"media":{"duration":90.0}}]}"#
            ).framed()
        )
    }

    @Test func readsTheReportedMediaStatus() async throws {
        let (client, transport) = try await connectClient()
        try await connectAndReportMedia(client, transport, state: "PAUSED")

        let status = try #require(client.mediaStatus)
        #expect(status.mediaSessionID == 7)
        #expect(status.playerState == .paused)
        #expect(status.position == 5.5)
        #expect(status.duration == 90)
    }

    @Test func keepsTheDurationWhenAnUpdateOmitsIt() async throws {
        let (client, transport) = try await connectClient()
        try await connectAndReportMedia(client, transport)
        #expect(client.mediaStatus?.duration == 90)

        client.handle(
            CastMessage(
                sourceID: "web-5",
                destinationID: CastClient.senderID,
                namespace: CastClient.Namespace.media,
                payload: #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":7,"playerState":"PAUSED","currentTime":12.0}]}"#
            ).framed()
        )

        #expect(client.mediaStatus?.duration == 90)
        #expect(client.mediaStatus?.position == 12)
        #expect(client.mediaStatus?.playerState == .paused)
    }

    @Test func sendsPlaybackCommandsWithRequestIds() async throws {
        let (client, transport) = try await connectClient()
        try await connectAndReportMedia(client, transport)

        await client.pause()
        await client.play()
        await client.seek(to: 42)

        let mediaCommands = transport.sentMessages.filter { $0.namespace == CastClient.Namespace.media }
        let types = mediaCommands.compactMap { message -> String? in
            guard let data = message.payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            return object["type"] as? String
        }
        #expect(types == ["PAUSE", "PLAY", "SEEK"])

        let seek = try #require(mediaCommands.last)
        let seekPayload = try #require(
            try JSONSerialization.jsonObject(with: Data(seek.payload.utf8)) as? [String: Any]
        )
        #expect(seekPayload["currentTime"] as? Double == 42)
        #expect(seekPayload["mediaSessionId"] as? Int == 7)
        #expect(seekPayload["requestId"] as? Int != nil)
    }

    @Test func ignoresPlaybackCommandsWithoutAMediaSession() async throws {
        let (client, transport) = try await connectClient()

        await client.play()

        #expect(!transport.sentMessages.contains { $0.namespace == CastClient.Namespace.media })
    }

    @Test func stopsOnlyTheMediaPlayback() async throws {
        let (client, transport) = try await connectClient()
        let launch = Task { try await client.launchDefaultReceiver() }
        await transport.waitForSentFrames(2)
        transport.push(
            CastMessage(
                sourceID: CastClient.receiverID,
                destinationID: CastClient.senderID,
                namespace: CastClient.Namespace.receiver,
                payload: #"{"type":"RECEIVER_STATUS","status":{"applications":[{"appId":"CC1AD845","transportId":"web-5","sessionId":"session-1"}]}}"#
            )
        )
        _ = try await launch.value
        client.handle(
            CastMessage(
                sourceID: "web-5",
                destinationID: CastClient.senderID,
                namespace: CastClient.Namespace.media,
                payload: #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":7,"playerState":"PLAYING"}]}"#
            ).framed()
        )

        await client.stopMedia()

        let sent = transport.sentMessages
        let stopMedia = try #require(sent.first { $0.namespace == CastClient.Namespace.media })
        #expect(stopMedia.payload.contains(#""mediaSessionId":7"#))
        #expect(!sent.contains { $0.namespace == CastClient.Namespace.receiver && $0.payload.contains(#""type":"STOP""#) })
        #expect(!sent.contains { $0.payload == #"{"type":"CLOSE"}"# })
        #expect(!transport.isClosed)
    }

    @Test func answersHeartbeatPings() async throws {
        let (client, transport) = try await connectClient()
        defer { client.disconnect() }

        transport.push(
            CastMessage(
                sourceID: CastClient.receiverID,
                destinationID: CastClient.senderID,
                namespace: CastClient.Namespace.heartbeat,
                payload: #"{"type":"PING"}"#
            )
        )

        await transport.waitForSentFrames(2)
        let reply = try #require(transport.sentMessages.last)
        #expect(reply.namespace == CastClient.Namespace.heartbeat)
        #expect(reply.destinationID == CastClient.receiverID)
        #expect(reply.payload == #"{"type":"PONG"}"#)
    }

    @Test func sendsHeartbeatsOnItsOwn() async throws {
        let (client, transport) = try await connectClient(heartbeat: .milliseconds(50))
        defer { client.disconnect() }

        await transport.waitForSentFrames(2)

        let ping = try #require(transport.sentMessages.last)
        #expect(ping.namespace == CastClient.Namespace.heartbeat)
        #expect(ping.payload == #"{"type":"PING"}"#)
    }

    @Test func failsAPendingLaunchWhenTheConnectionEnds() async throws {
        let (client, transport) = try await connectClient(launchTimeout: .seconds(2))
        let launch = Task { try await client.launchDefaultReceiver() }
        await transport.waitForSentFrames(2)

        transport.close()

        await #expect(throws: CastClient.ClientError.notConnected) {
            try await launch.value
        }
    }

    @Test func refusesCommandsWithoutAConnection() async {
        let client = CastClient(transport: ScriptedCastTransport())

        await #expect(throws: CastClient.ClientError.notConnected) {
            try await client.launchDefaultReceiver()
        }
        await #expect(throws: CastClient.ClientError.notConnected) {
            try await client.load(
                CastClient.Media(contentURL: URL(fileURLWithPath: "/tmp/a.mp4"), contentType: "video/mp4"),
                transportID: "web-5"
            )
        }
    }
}
