import Foundation
import UniformTypeIdentifiers

/// Serves one selected file over the local network for a casting session.
protocol MediaServing: Sendable {
    /// Starts serving `file` and returns the URL a receiver can fetch.
    func startServing(_ file: MediaFile) async throws -> URL
    /// Stops serving and releases the port.
    func stopServing()
}

extension LocalMediaServer: MediaServing {
    func startServing(_ file: MediaFile) async throws -> URL {
        try await start(file: file).url
    }

    func stopServing() {
        stop()
    }
}

/// A connected Cast session that can receive media.
@MainActor
protocol CastMediaLoading: AnyObject {
    /// Whether a session is open and ready for a load command.
    var isConnected: Bool { get }
    /// Asks the running receiver to load `media`.
    func load(_ media: CastClient.Media) async throws
}

/// Drives one casting session: serve the file locally, then ask the device to play it.
///
/// The model owns the server lifetime, so the file is reachable exactly while a cast is
/// active, and it stops serving when the cast ends or fails. The device confirms that it
/// accepted the load; what it reports about playback state is handled by the playback
/// phase.
@MainActor
@Observable
final class PlaybackModel {
    enum State: Equatable {
        /// Nothing is being cast.
        case idle
        /// The server is starting or the device is being asked to load.
        case starting
        /// The device accepted the media URL.
        case casting(url: URL)
        /// The cast could not start; the message is ready for display.
        case failed(String)
    }

    private(set) var state: State = .idle

    private let server: any MediaServing

    init(server: any MediaServing = LocalMediaServer()) {
        self.server = server
    }

    /// Serves `file` locally and asks `device` to play it.
    func play(file: MediaFile, connection: any CastMediaLoading) async {
        guard connection.isConnected else {
            state = .failed("Connect to a device before casting.")
            return
        }

        stop()
        state = .starting

        do {
            let url = try await server.startServing(file)
            let media = CastClient.Media(
                contentURL: url,
                contentType: Self.contentType(for: file),
                title: file.name
            )
            try await connection.load(media)
            state = .casting(url: url)
        } catch {
            server.stopServing()
            state = .failed(Self.message(for: error))
        }
    }

    /// Stops serving the file.
    func stop() {
        server.stopServing()
        state = .idle
    }

    /// Stops serving the file and closes the session with the device.
    func stopAndDisconnect(connection: CastConnectionModel) async {
        await connection.disconnect()
        stop()
    }

    /// MIME type the receiver should use for `file`.
    static func contentType(for file: MediaFile) -> String {
        guard let fileExtension = file.format.fileExtension,
              let type = UTType(filenameExtension: fileExtension)?.preferredMIMEType else {
            return "video/mp4"
        }
        return type
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
