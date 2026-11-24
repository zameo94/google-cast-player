import Foundation
import Testing
@testable import GoogleCastPlayer

struct MediaMetadataTests {
    @Test func mapsKnownVideoCodecs() {
        #expect(VideoCodec(fourCC: "avc1") == .h264)
        #expect(VideoCodec(fourCC: "avc3") == .h264)
        #expect(VideoCodec(fourCC: "hvc1") == .hevc)
        #expect(VideoCodec(fourCC: "hev1") == .hevc)
    }

    @Test func keepsUnknownVideoCodecNames() {
        #expect(VideoCodec(fourCC: "vp09") == .other(name: "VP09"))
        #expect(VideoCodec(fourCC: "vp09").displayName == "VP09")
        #expect(VideoCodec(fourCC: "").displayName == "Unknown video codec")
    }

    @Test func mapsKnownAudioCodecs() {
        #expect(AudioCodec(fourCC: "mp4a") == .aac)
        #expect(AudioCodec(fourCC: "mp4a").displayName == "AAC")
        #expect(AudioCodec(fourCC: "alac") == .other(name: "ALAC"))
        #expect(AudioCodec(fourCC: "").displayName == "Unknown audio codec")
    }

    @Test func namesKnownCodecsForDisplay() {
        #expect(VideoCodec.h264.displayName == "H.264")
        #expect(VideoCodec.hevc.displayName == "HEVC")
        #expect(AudioCodec.aac.displayName == "AAC")
    }
}
