import Foundation
@testable import GoogleCastPlayer

/// Access double that records which URLs were granted and released.
final class FileAccessSpy: FileAccessControlling {
    private(set) var startedURLs: [URL] = []
    private(set) var stoppedURLs: [URL] = []
    /// Whether the system would report a security scope for the URL.
    var grantsAccess = true

    @discardableResult
    func startAccessing(_ url: URL) -> Bool {
        startedURLs.append(url)
        return grantsAccess
    }

    func stopAccessing(_ url: URL) {
        stoppedURLs.append(url)
    }
}

/// Extractor double that returns a fixed result.
struct StubMetadataExtractor: MediaMetadataExtracting {
    let result: Result<MediaMetadata, MediaMetadataError>

    func extractMetadata(from url: URL) async throws -> MediaMetadata {
        try result.get()
    }
}

/// Extractor double that stalls inside extraction until the test releases it.
actor StalledMetadataExtractor: MediaMetadataExtracting {
    private let metadata: MediaMetadata
    private var hasStarted = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    init(metadata: MediaMetadata) {
        self.metadata = metadata
    }

    func extractMetadata(from url: URL) async throws -> MediaMetadata {
        hasStarted = true
        for waiter in startWaiters {
            waiter.resume()
        }
        startWaiters.removeAll()
        await withCheckedContinuation { releaseWaiter = $0 }
        return metadata
    }

    /// Suspends until extraction has been entered.
    func waitUntilExtractionStarts() async {
        if hasStarted {
            return
        }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    /// Lets the stalled extraction finish.
    func releaseExtraction() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

extension MediaMetadata {
    /// Metadata matching the playback profile the app targets.
    static let targetProfile = MediaMetadata(
        duration: .seconds(42),
        videoTracks: [VideoTrack(codec: .h264, width: 1280, height: 720)],
        audioTracks: [AudioTrack(codec: .aac)]
    )
}

/// Browser double that emits nothing, for tests that drive the model directly.
struct SilentCastDeviceBrowser: CastDeviceBrowsing {
    func events() -> AsyncStream<CastDiscoveryEvent> {
        AsyncStream { _ in }
    }
}
