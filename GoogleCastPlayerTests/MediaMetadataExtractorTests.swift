import Foundation
import Testing
@testable import GoogleCastPlayer

/// Anchors the test bundle so its resources can be located.
private final class TestBundleAnchor {}

struct MediaMetadataExtractorTests {
    private let extractor = MediaMetadataExtractor()

    @Test func readsMetadataFromAnH264Movie() async throws {
        let url = try #require(
            Bundle(for: TestBundleAnchor.self).url(forResource: "sample-h264", withExtension: "mp4"),
            "The sample-h264.mp4 fixture is missing from the test bundle"
        )

        let metadata = try await extractor.extractMetadata(from: url)

        let track = try #require(metadata.videoTracks.first)
        #expect(track.codec == .h264)
        #expect(track.width == 160)
        #expect(track.height == 120)
        #expect(metadata.videoTracks.count == 1)
        #expect(metadata.audioTracks.isEmpty)

        let duration = try #require(metadata.duration)
        #expect(abs(duration.inSeconds - 1.0) < 0.1)
    }

    @Test func reportsUnreadableFile() async {
        let url = TestFixture.missingFileURL(named: "missing.mp4")

        await #expect(throws: MediaMetadataError.notReadable(name: "missing.mp4")) {
            try await extractor.extractMetadata(from: url)
        }
    }

    @Test func doesNotInventTracksForUnreadableContent() async throws {
        let url = try TestFixture.file(named: "garbage.mp4", contents: Data("not a video".utf8))
        defer { TestFixture.remove(url) }

        let metadata = try? await extractor.extractMetadata(from: url)
        if let metadata {
            #expect(metadata.videoTracks.isEmpty)
            #expect(metadata.audioTracks.isEmpty)
        }
    }
}

private extension Duration {
    /// The duration expressed in seconds.
    var inSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
