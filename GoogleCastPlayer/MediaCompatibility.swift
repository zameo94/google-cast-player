import Foundation

/// Verdict about whether a media file matches the playback profile the app targets:
/// MP4 container, H.264 video, AAC audio.
struct MediaCompatibility: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// Every checked property matches the target profile.
        case compatible
        /// At least one property could not be verified; playback may still work.
        case uncertain
        /// A verified property is outside the target profile.
        case unsupported
    }

    let status: Status
    /// Explanations for anything other than full compatibility, ready for display.
    let reasons: [String]

    static let compatible = MediaCompatibility(status: .compatible, reasons: [])
}

/// Judges extracted metadata against the playback profile the app targets.
///
/// The evaluator is pure: it receives metadata that was already extracted and never
/// decodes media. It describes files, not devices: a receiver may accept more than
/// this profile, but the app does not promise it.
struct MediaCompatibilityEvaluator: Sendable {
    /// Containers the profile targets directly.
    static let prioritizedContainerExtensions: Set<String> = ["mp4", "m4v"]
    /// Containers that usually work but are not the prioritized target.
    static let toleratedContainerExtensions: Set<String> = ["mov"]

    func assess(metadata: MediaMetadata, format: MediaFormat) -> MediaCompatibility {
        var unsupportedReasons: [String] = []
        var uncertainReasons: [String] = []

        switch containerVerdict(for: format) {
        case .compatible:
            break
        case let .uncertain(reason):
            uncertainReasons.append(reason)
        case let .unsupported(reason):
            unsupportedReasons.append(reason)
        }

        if metadata.videoTracks.isEmpty {
            unsupportedReasons.append("The file reports no video track.")
        }

        for track in metadata.videoTracks {
            switch track.codec {
            case .h264:
                break
            case .hevc:
                unsupportedReasons.append("The video uses HEVC; the app targets H.264.")
            case let .other(name):
                if name.isEmpty {
                    uncertainReasons.append("The video codec could not be determined.")
                } else {
                    unsupportedReasons.append("The video codec \(name) is not supported; the app targets H.264.")
                }
            }
        }

        for track in metadata.audioTracks {
            switch track.codec {
            case .aac:
                break
            case let .other(name):
                if name.isEmpty {
                    uncertainReasons.append("The audio codec could not be determined.")
                } else {
                    unsupportedReasons.append("The audio codec \(name) is not supported; the app targets AAC.")
                }
            }
        }

        if !unsupportedReasons.isEmpty {
            return MediaCompatibility(status: .unsupported, reasons: unsupportedReasons + uncertainReasons)
        }
        if !uncertainReasons.isEmpty {
            return MediaCompatibility(status: .uncertain, reasons: uncertainReasons)
        }
        return .compatible
    }

    private enum ContainerVerdict {
        case compatible
        case uncertain(String)
        case unsupported(String)
    }

    private func containerVerdict(for format: MediaFormat) -> ContainerVerdict {
        guard let fileExtension = format.fileExtension, !fileExtension.isEmpty else {
            return .uncertain("The container could not be determined from the file name.")
        }
        if Self.prioritizedContainerExtensions.contains(fileExtension) {
            return .compatible
        }
        if Self.toleratedContainerExtensions.contains(fileExtension) {
            return .uncertain(
                "The container is \(format.displayName); MP4 is the prioritized container."
            )
        }
        return .unsupported(
            "The container \(format.displayName) is not supported; the app targets MP4."
        )
    }
}
