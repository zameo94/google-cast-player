import AVFoundation
import CoreMedia
import Foundation

/// Reads the technical metadata a local media file reports.
protocol MediaMetadataExtracting: Sendable {
    /// Extracts the metadata available for the file at `url`.
    ///
    /// - Throws: `MediaMetadataError` when the file cannot be read.
    func extractMetadata(from url: URL) async throws -> MediaMetadata
}

/// Metadata extraction backed by AVFoundation.
///
/// Only properties the container actually reports are read; nothing is decoded and
/// no playback is prepared. Unknown properties stay unknown instead of being invented.
struct MediaMetadataExtractor: MediaMetadataExtracting {
    func extractMetadata(from url: URL) async throws -> MediaMetadata {
        let asset = AVURLAsset(url: url)

        do {
            let duration = try await asset.load(.duration)
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)

            var videos: [MediaMetadata.VideoTrack] = []
            for track in videoTracks {
                let descriptions = try await track.load(.formatDescriptions)
                let size = try await track.load(.naturalSize)
                videos.append(
                    MediaMetadata.VideoTrack(
                        codec: VideoCodec(fourCC: descriptions.first.map(Self.fourCCString) ?? ""),
                        width: Int(size.width.rounded()),
                        height: Int(size.height.rounded())
                    )
                )
            }

            var audios: [MediaMetadata.AudioTrack] = []
            for track in audioTracks {
                let descriptions = try await track.load(.formatDescriptions)
                audios.append(
                    MediaMetadata.AudioTrack(
                        codec: AudioCodec(fourCC: descriptions.first.map(Self.fourCCString) ?? "")
                    )
                )
            }

            return MediaMetadata(
                duration: Self.duration(from: duration),
                videoTracks: videos,
                audioTracks: audios
            )
        } catch {
            throw MediaMetadataError.notReadable(name: url.lastPathComponent)
        }
    }

    private static func duration(from time: CMTime) -> Duration? {
        guard time.isValid, time.isNumeric, !time.isIndefinite, time.seconds > 0 else {
            return nil
        }
        return .seconds(time.seconds)
    }

    /// Formats the media subtype of a format description as its FourCC code.
    private static func fourCCString(_ description: CMFormatDescription) -> String {
        let code = CMFormatDescriptionGetMediaSubType(description)
        guard code != 0 else {
            return ""
        }
        let bytes = (0..<4).map { UInt8((code >> (24 - 8 * $0)) & 0xFF) }
        let nullsAndSpaces = CharacterSet(charactersIn: "\0").union(.whitespaces)
        return String(bytes: bytes, encoding: .isoLatin1)?
            .trimmingCharacters(in: nullsAndSpaces) ?? ""
    }
}

/// Reasons the app cannot describe a media file.
enum MediaMetadataError: Error, Equatable, LocalizedError {
    /// The system could not open the container.
    case notReadable(name: String)

    var errorDescription: String? {
        switch self {
        case let .notReadable(name):
            return "\u{201C}\(name)\u{201D} could not be read. The file may be damaged or use a container the system cannot open."
        }
    }
}
