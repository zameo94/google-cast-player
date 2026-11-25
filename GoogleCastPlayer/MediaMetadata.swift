import Foundation

/// Technical description of a media file, as far as the local file reports it.
///
/// The type is a plain value: extraction produces it, the compatibility assessment
/// consumes it, and the interface presents it. It never holds SwiftUI or player state.
struct MediaMetadata: Equatable, Sendable {
    /// Duration reported by the container, or `nil` when it cannot be determined.
    let duration: Duration?
    /// Video tracks, normally one.
    let videoTracks: [VideoTrack]
    /// Audio tracks, possibly empty for silent video.
    let audioTracks: [AudioTrack]

    struct VideoTrack: Equatable, Sendable {
        /// Codec reported by the container.
        let codec: VideoCodec
        /// Encoded width in pixels.
        let width: Int
        /// Encoded height in pixels.
        let height: Int
    }

    struct AudioTrack: Equatable, Sendable {
        /// Codec reported by the container.
        let codec: AudioCodec
    }
}

/// Video codec identifier reported by the container.
enum VideoCodec: Equatable, Sendable {
    case h264
    case hevc
    case other(name: String)

    /// Maps a FourCC code such as `avc1` to a known codec.
    ///
    /// An empty code means the container did not report one.
    init(fourCC: String) {
        switch fourCC {
        case "avc1", "avc3":
            self = .h264
        case "hvc1", "hev1":
            self = .hevc
        default:
            self = .other(name: fourCC.uppercased())
        }
    }

    /// Label for the user, for example "H.264".
    var displayName: String {
        switch self {
        case .h264:
            return "H.264"
        case .hevc:
            return "HEVC"
        case let .other(name):
            return name.isEmpty ? "Unknown video codec" : name
        }
    }
}

/// Audio codec identifier reported by the container.
enum AudioCodec: Equatable, Sendable {
    case aac
    case other(name: String)

    /// Maps a FourCC code such as `mp4a` to a known codec.
    ///
    /// The AAC family appears under more than one identifier: `aac` and `aacp` are
    /// reported for plain and parameterized AAC, while `mp4a` is the MPEG-4 audio
    /// object type used by some containers. An empty code means the container did
    /// not report one.
    init(fourCC: String) {
        switch fourCC {
        case "aac", "aacp", "aach", "mp4a":
            self = .aac
        default:
            self = .other(name: fourCC.uppercased())
        }
    }

    /// Label for the user, for example "AAC".
    var displayName: String {
        switch self {
        case .aac:
            return "AAC"
        case let .other(name):
            return name.isEmpty ? "Unknown audio codec" : name
        }
    }
}
