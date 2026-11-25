import Foundation
import Testing
@testable import GoogleCastPlayer

struct MediaCompatibilityEvaluatorTests {
    private let evaluator = MediaCompatibilityEvaluator()

    @Test func acceptsTheTargetProfile() {
        let compatibility = evaluator.assess(metadata: .targetProfile, format: MediaFormat(fileExtension: "mp4"))

        #expect(compatibility.status == .compatible)
        #expect(compatibility.reasons.isEmpty)
    }

    @Test func acceptsM4VContainer() {
        let compatibility = evaluator.assess(metadata: .targetProfile, format: MediaFormat(fileExtension: "m4v"))

        #expect(compatibility.status == .compatible)
    }

    @Test func acceptsSilentVideo() {
        let metadata = MediaMetadata(duration: .seconds(5), videoTracks: [.h264], audioTracks: [])
        let compatibility = evaluator.assess(metadata: metadata, format: MediaFormat(fileExtension: "mp4"))

        #expect(compatibility.status == .compatible)
    }

    @Test func acceptsUnknownDuration() {
        let metadata = MediaMetadata(duration: nil, videoTracks: [.h264], audioTracks: [.init(codec: .aac)])
        let compatibility = evaluator.assess(metadata: metadata, format: MediaFormat(fileExtension: "mp4"))

        #expect(compatibility.status == .compatible)
    }

    @Test func reportsMovieContainerAsUncertain() {
        let compatibility = evaluator.assess(metadata: .targetProfile, format: MediaFormat(fileExtension: "mov"))

        #expect(compatibility.status == .uncertain)
        #expect(compatibility.reasons.count == 1)
        #expect(compatibility.reasons[0].contains("MP4"))
    }

    @Test func rejectsUnsupportedContainer() {
        let compatibility = evaluator.assess(metadata: .targetProfile, format: MediaFormat(fileExtension: "avi"))

        #expect(compatibility.status == .unsupported)
        #expect(compatibility.reasons[0].contains("AVI"))
    }

    @Test func reportsMissingContainerAsUncertain() {
        let compatibility = evaluator.assess(metadata: .targetProfile, format: MediaFormat(fileExtension: nil))

        #expect(compatibility.status == .uncertain)
    }

    @Test func rejectsHEVCVideo() {
        let metadata = MediaMetadata(
            duration: .seconds(5),
            videoTracks: [.init(codec: .hevc, width: 1920, height: 1080)],
            audioTracks: [.init(codec: .aac)]
        )
        let compatibility = evaluator.assess(metadata: metadata, format: MediaFormat(fileExtension: "mp4"))

        #expect(compatibility.status == .unsupported)
        #expect(compatibility.reasons.contains { $0.contains("HEVC") })
    }

    @Test func rejectsOtherVideoCodec() {
        let metadata = MediaMetadata(
            duration: nil,
            videoTracks: [.init(codec: .other(name: "VP09"), width: 1280, height: 720)],
            audioTracks: []
        )
        let compatibility = evaluator.assess(metadata: metadata, format: MediaFormat(fileExtension: "mp4"))

        #expect(compatibility.status == .unsupported)
        #expect(compatibility.reasons.contains { $0.contains("VP09") })
    }

    @Test func reportsUnknownVideoCodecAsUncertain() {
        let metadata = MediaMetadata(
            duration: nil,
            videoTracks: [.init(codec: .other(name: ""), width: 640, height: 480)],
            audioTracks: []
        )
        let compatibility = evaluator.assess(metadata: metadata, format: MediaFormat(fileExtension: "mp4"))

        #expect(compatibility.status == .uncertain)
    }

    @Test func rejectsFileWithoutVideoTrack() {
        let metadata = MediaMetadata(duration: nil, videoTracks: [], audioTracks: [.init(codec: .aac)])
        let compatibility = evaluator.assess(metadata: metadata, format: MediaFormat(fileExtension: "mp4"))

        #expect(compatibility.status == .unsupported)
        #expect(compatibility.reasons.contains { $0.contains("no video track") })
    }

    @Test func rejectsUnsupportedAudioCodec() {
        let metadata = MediaMetadata(
            duration: nil,
            videoTracks: [.h264],
            audioTracks: [.init(codec: .other(name: "ALAC"))]
        )
        let compatibility = evaluator.assess(metadata: metadata, format: MediaFormat(fileExtension: "mp4"))

        #expect(compatibility.status == .unsupported)
        #expect(compatibility.reasons.contains { $0.contains("ALAC") })
    }

    @Test func reportsUnknownAudioCodecAsUncertain() {
        let metadata = MediaMetadata(
            duration: nil,
            videoTracks: [.h264],
            audioTracks: [.init(codec: .other(name: ""))]
        )
        let compatibility = evaluator.assess(metadata: metadata, format: MediaFormat(fileExtension: "mp4"))

        #expect(compatibility.status == .uncertain)
    }

    @Test func keepsUnsupportedAndUncertainReasonsTogether() {
        let metadata = MediaMetadata(
            duration: nil,
            videoTracks: [.init(codec: .hevc, width: 1920, height: 1080)],
            audioTracks: [.init(codec: .other(name: ""))]
        )
        let compatibility = evaluator.assess(metadata: metadata, format: MediaFormat(fileExtension: "mp4"))

        #expect(compatibility.status == .unsupported)
        #expect(compatibility.reasons.count == 2)
    }
}

private extension MediaMetadata.VideoTrack {
    static let h264 = MediaMetadata.VideoTrack(codec: .h264, width: 1920, height: 1080)
}
