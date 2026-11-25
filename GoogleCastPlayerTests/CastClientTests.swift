import Foundation
import Testing
@testable import GoogleCastPlayer

/// Transport double that records what the client sends and delivers what the test pushes.
final class ScriptedCastTransport: CastTransporting, @unchecked Sendable {
    private struct Waiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private let lock = NSLock()
    private var sentStorage: [Data] = []
    private var waiters: [Waiter] = []
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

    func close() {
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
        heartbeat: Duration = .seconds(60)
    ) async throws -> (CastClient, ScriptedCastTransport) {
        let transport = ScriptedCastTransport()
        let client = CastClient(transport: transport, launchTimeout: launchTimeout, heartbeatInterval: heartbeat)
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
        let (client, transport) = try await connectClient(launchTimeout: .milliseconds(300))
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

        await #expect(throws: CastClient.ClientError.receiverLaunchTimedOut) {
            try await launch.value
        }
    }

    @Test func reportsATimedOutLaunch() async throws {
        let (client, transport) = try await connectClient(launchTimeout: .milliseconds(100))
        let launch = Task { try await client.launchDefaultReceiver() }
        await transport.waitForSentFrames(2)

        await #expect(throws: CastClient.ClientError.receiverLaunchTimedOut) {
            try await launch.value
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
