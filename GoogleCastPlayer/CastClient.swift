import Foundation

/// Waits for a duration; injected so timeouts can be tested without wall-clock waits.
protocol Sleeping: Sendable {
    func sleep(for duration: Duration) async
}

struct TaskSleeper: Sleeping {
    func sleep(for duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}

/// Drives the Cast V2 handshake over a transport.
///
/// The client speaks the parts of the protocol the app needs: the connection namespace,
/// the heartbeat, launching the default media receiver, and sending a load command. It
/// does not manage playback state; that belongs to the playback phase.
@MainActor
final class CastClient {
    enum ClientError: Error, Equatable, LocalizedError {
        case notConnected
        case receiverLaunchTimedOut
        case receiverRejected

        var errorDescription: String? {
            switch self {
            case .notConnected:
                return "The device is not connected."
            case .receiverLaunchTimedOut:
                return "The device did not start the receiver in time."
            case .receiverRejected:
                return "The device refused to start the receiver."
            }
        }
    }

    /// Media the receiver should load.
    struct Media: Equatable, Sendable {
        let contentURL: URL
        let contentType: String
        /// `BUFFERED` for a progressive HTTP source.
        let streamType: String
        let title: String?

        init(contentURL: URL, contentType: String, streamType: String = "BUFFERED", title: String? = nil) {
            self.contentURL = contentURL
            self.contentType = contentType
            self.streamType = streamType
            self.title = title
        }
    }

    /// What the receiver reports about the media it is playing.
    struct MediaStatus: Equatable, Sendable {
        enum PlayerState: String, Equatable, Sendable {
            case playing = "PLAYING"
            case paused = "PAUSED"
            case buffering = "BUFFERING"
            case idle = "IDLE"
            case unknown = "UNKNOWN"
        }

        /// Identifier the receiver uses for this media session.
        let mediaSessionID: Int
        /// State the receiver reports.
        let playerState: PlayerState
        /// Playback position the receiver reported, in seconds.
        let position: TimeInterval?
        /// Duration of the media, in seconds.
        let duration: TimeInterval?
        /// Why the media went idle, when the receiver says so.
        let idleReason: String?
    }

    enum Namespace {
        static let connection = "urn:x-cast:com.google.cast.tp.connection"
        static let heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
        static let receiver = "urn:x-cast:com.google.cast.receiver"
        static let media = "urn:x-cast:com.google.cast.media"
    }

    static let senderID = "sender-0"
    static let receiverID = "receiver-0"
    /// The Default Media Receiver every Cast device can run without a custom app.
    static let defaultMediaReceiverAppID = "CC1AD845"

    private struct PendingLaunch {
        let appID: String
        let continuation: CheckedContinuation<String, any Error>
    }

    private let transport: any CastTransporting
    private let launchTimeout: Duration
    private let heartbeatInterval: Duration
    private let sleeper: any Sleeping

    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var launchTimeoutTask: Task<Void, Never>?
    private var pendingLaunch: PendingLaunch?
    private var receiverTransportID: String?
    private var receiverSessionID: String?
    private var mediaSessionID: Int?
    /// Last media status the receiver reported.
    private(set) var mediaStatus: MediaStatus?
    /// Called on every media status the receiver reports.
    var onMediaStatus: ((MediaStatus?) -> Void)?
    private var receiverBuffer = Data()
    private var nextRequestID = 1
    private var isConnected = false

    init(
        transport: any CastTransporting,
        launchTimeout: Duration = .seconds(10),
        heartbeatInterval: Duration = .seconds(5),
        sleeper: any Sleeping = TaskSleeper()
    ) {
        self.transport = transport
        self.launchTimeout = launchTimeout
        self.heartbeatInterval = heartbeatInterval
        self.sleeper = sleeper
    }

    /// Opens the transport and announces the sender to the receiver.
    func connect() async throws {
        try await transport.connect()
        isConnected = true
        try await send(
            CastMessage(
                sourceID: Self.senderID,
                destinationID: Self.receiverID,
                namespace: Namespace.connection,
                payload: #"{"type":"CONNECT"}"#
            )
        )
        startReceiving()
        startHeartbeat()
    }

    /// Launches the Default Media Receiver and returns its transport id.
    func launchDefaultReceiver() async throws -> String {
        try await launch(appID: Self.defaultMediaReceiverAppID)
    }

    /// Launches a receiver application and returns its transport id.
    func launch(appID: String) async throws -> String {
        guard isConnected else {
            throw ClientError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingLaunch = PendingLaunch(appID: appID, continuation: continuation)
            let requestID = takeRequestID()
            let payload = #"{"type":"LAUNCH","appId":"\#(appID)","requestId":\#(requestID)}"#
            let message = CastMessage(
                sourceID: Self.senderID,
                destinationID: Self.receiverID,
                namespace: Namespace.receiver,
                payload: payload
            )
            Task { @MainActor in
                do {
                    try await self.send(message)
                    self.scheduleLaunchTimeout()
                } catch {
                    self.finishLaunch(.failure(error))
                }
            }
        }
    }

    /// Connects to a running receiver application and sends a load command.
    ///
    /// - Returns: The request id the receiver answers with.
    @discardableResult
    func load(_ media: Media, transportID: String) async throws -> Int {
        guard isConnected else {
            throw ClientError.notConnected
        }
        try await send(
            CastMessage(
                sourceID: Self.senderID,
                destinationID: transportID,
                namespace: Namespace.connection,
                payload: #"{"type":"CONNECT"}"#
            )
        )

        let requestID = takeRequestID()
        mediaSessionID = nil
        mediaStatus = nil
        onMediaStatus?(nil)
        try await send(
            CastMessage(
                sourceID: Self.senderID,
                destinationID: transportID,
                namespace: Namespace.media,
                payload: Self.loadPayload(media: media, requestID: requestID)
            )
        )
        return requestID
    }

    /// Resumes the media that is paused.
    func play() async {
        await sendMediaCommand("PLAY")
    }

    /// Pauses the media that is playing.
    func pause() async {
        await sendMediaCommand("PAUSE")
    }

    /// Moves the playing media to `position`, in seconds.
    func seek(to position: TimeInterval) async {
        await sendMediaCommand("SEEK", fields: ["currentTime": position])
    }

    private func sendMediaCommand(_ type: String, fields: [String: Any] = [:]) async {
        guard isConnected,
              let transportID = receiverTransportID,
              let mediaSessionID else {
            return
        }
        var object: [String: Any] = [
            "type": type,
            "requestId": takeRequestID(),
            "mediaSessionId": mediaSessionID,
        ]
        for (key, value) in fields {
            object[key] = value
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return
        }
        try? await send(
            CastMessage(
                sourceID: Self.senderID,
                destinationID: transportID,
                namespace: Namespace.media,
                payload: String(decoding: data, as: UTF8.self)
            )
        )
    }

    /// Stops the media that is playing, and nothing else.
    ///
    /// The session stays open, so the device keeps its receiver screen and the sender
    /// can load another media without reconnecting.
    func stopMedia() async {
        await sendMediaCommand("STOP")
        mediaSessionID = nil
        mediaStatus = nil
        onMediaStatus?(nil)
    }

    /// Stops the media and the receiver application, then closes the transport.
    ///
    /// Closing the socket alone leaves the receiver playing, so the session is ended
    /// explicitly: the media is stopped, the receiver application is stopped, and only
    /// then the connection is closed. Commands are best effort, because the device may
    /// already be gone.
    func endSession() async {
        await stopMedia()
        if isConnected {
            // A device that did not report a session id can still stop its current app.
            let payload = if let receiverSessionID {
                #"{"type":"STOP","requestId":\#(takeRequestID()),"sessionId":"\#(receiverSessionID)"}"#
            } else {
                #"{"type":"STOP","requestId":\#(takeRequestID())}"#
            }
            try? await send(
                CastMessage(
                    sourceID: Self.senderID,
                    destinationID: Self.receiverID,
                    namespace: Namespace.receiver,
                    payload: payload
                )
            )
        }
        if isConnected {
            try? await send(
                CastMessage(
                    sourceID: Self.senderID,
                    destinationID: Self.receiverID,
                    namespace: Namespace.connection,
                    payload: #"{"type":"CLOSE"}"#
                )
            )
        }
        disconnect()
    }

    /// Closes the transport and stops the background work.
    func disconnect() {
        isConnected = false
        receiveTask?.cancel()
        heartbeatTask?.cancel()
        launchTimeoutTask?.cancel()
        receiveTask = nil
        heartbeatTask = nil
        launchTimeoutTask = nil
        finishLaunch(.failure(ClientError.notConnected))
        transport.close()
    }

    // MARK: - Incoming messages

    /// Applies bytes received from the device.
    ///
    /// Kept internal so tests can drive the protocol without a socket.
    func handle(_ data: Data) {
        receiverBuffer.append(data)
        let (messages, remainder) = CastMessage.frames(in: receiverBuffer)
        receiverBuffer = remainder

        for message in messages {
            handle(message)
        }
    }

    private func handle(_ message: CastMessage) {
        switch message.namespace {
        case Namespace.heartbeat:
            handleHeartbeat(message)
        case Namespace.receiver:
            handleReceiver(message)
        case Namespace.media:
            handleMedia(message)
        default:
            break
        }
    }

    private func handleHeartbeat(_ message: CastMessage) {
        guard Self.payloadType(of: message) == "PING" else {
            return
        }
        let reply = CastMessage(
            sourceID: Self.senderID,
            destinationID: message.sourceID,
            namespace: Namespace.heartbeat,
            payload: #"{"type":"PONG"}"#
        )
        Task { @MainActor in
            try? await self.send(reply)
        }
    }

    private func handleReceiver(_ message: CastMessage) {
        guard let pendingLaunch else {
            return
        }
        guard let application = Self.application(in: message.payload, forAppID: pendingLaunch.appID) else {
            // A receiver status can also report that the app stopped.
            if Self.hasStoppedReceiver(in: message.payload) {
                receiverTransportID = nil
                receiverSessionID = nil
                mediaSessionID = nil
                mediaStatus = nil
                onMediaStatus?(nil)
            }
            return
        }
        receiverTransportID = application.transportID
        receiverSessionID = application.sessionID
        finishLaunch(.success(application.transportID))
    }

    private func handleMedia(_ message: CastMessage) {
        guard let data = message.payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "MEDIA_STATUS",
              let statuses = object["status"] as? [[String: Any]],
              let status = statuses.first,
              let mediaSessionID = status["mediaSessionId"] as? Int else {
            return
        }

        let rawState = status["playerState"] as? String
        let playerState = rawState.flatMap(MediaStatus.PlayerState.init(rawValue:)) ?? .unknown
        let media = status["media"] as? [String: Any]
        // Some updates omit the media block or the position; the last known value stands.
        let parsed = MediaStatus(
            mediaSessionID: mediaSessionID,
            playerState: playerState,
            position: (status["currentTime"] as? TimeInterval) ?? mediaStatus?.position,
            duration: (media?["duration"] as? TimeInterval) ?? mediaStatus?.duration,
            idleReason: (status["idleReason"] as? String) ?? mediaStatus?.idleReason
        )
        mediaStatus = parsed
        // An idle media cannot be controlled any more, but its status stays visible.
        self.mediaSessionID = playerState == .idle ? nil : mediaSessionID
        onMediaStatus?(parsed)
    }

    // MARK: - Background work

    private func startReceiving() {
        let transport = transport
        receiveTask = Task { [weak self] in
            while let chunk = await transport.receive() {
                guard let self, !Task.isCancelled else {
                    return
                }
                self.handle(chunk)
            }
            self?.connectionEnded()
        }
    }

    private func startHeartbeat() {
        let interval = heartbeatInterval
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self, !Task.isCancelled else {
                    return
                }
                try? await self.send(
                    CastMessage(
                        sourceID: Self.senderID,
                        destinationID: Self.receiverID,
                        namespace: Namespace.heartbeat,
                        payload: #"{"type":"PING"}"#
                    )
                )
            }
        }
    }

    private func scheduleLaunchTimeout() {
        let timeout = launchTimeout
        let sleeper = sleeper
        launchTimeoutTask?.cancel()
        launchTimeoutTask = Task { [weak self] in
            await sleeper.sleep(for: timeout)
            guard let self, !Task.isCancelled else {
                return
            }
            self.finishLaunch(.failure(ClientError.receiverLaunchTimedOut))
        }
    }

    private func connectionEnded() {
        guard isConnected else {
            return
        }
        isConnected = false
        finishLaunch(.failure(ClientError.notConnected))
    }

    // MARK: - Helpers

    private func send(_ message: CastMessage) async throws {
        guard isConnected else {
            throw ClientError.notConnected
        }
        try await transport.send(message.framed())
    }

    private func finishLaunch(_ result: Result<String, any Error>) {
        guard let pendingLaunch else {
            return
        }
        self.pendingLaunch = nil
        launchTimeoutTask?.cancel()
        launchTimeoutTask = nil
        pendingLaunch.continuation.resume(with: result)
    }

    private func takeRequestID() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }

    private static func loadPayload(media: Media, requestID: Int) -> String {
        var mediaObject: [String: Any] = [
            "contentId": media.contentURL.absoluteString,
            "streamType": media.streamType,
            "contentType": media.contentType,
        ]
        if let title = media.title {
            mediaObject["metadata"] = ["type": 0, "title": title]
        }
        let payload: [String: Any] = [
            "type": "LOAD",
            "requestId": requestID,
            "media": mediaObject,
            "autoplay": true,
            "currentTime": 0,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Reads the `type` field of a UTF-8 JSON payload.
    private static func payloadType(of message: CastMessage) -> String? {
        guard let data = message.payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["type"] as? String
    }

    /// Finds a running application in a receiver-status payload.
    private static func application(
        in payload: String,
        forAppID appID: String
    ) -> (transportID: String, sessionID: String?)? {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = object["status"] as? [String: Any],
              let applications = status["applications"] as? [[String: Any]],
              let application = applications.first(where: { $0["appId"] as? String == appID }),
              let transportID = application["transportId"] as? String else {
            return nil
        }
        return (transportID, application["sessionId"] as? String)
    }

    /// Whether a receiver-status payload reports that no application is running.
    private static func hasStoppedReceiver(in payload: String) -> Bool {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "RECEIVER_STATUS",
              let status = object["status"] as? [String: Any] else {
            return false
        }
        let applications = status["applications"] as? [[String: Any]] ?? []
        return applications.isEmpty
    }
}
