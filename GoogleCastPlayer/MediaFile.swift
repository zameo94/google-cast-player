import Foundation

/// A local video file imported by the user for playback on a Cast device.
///
/// The type is intentionally independent of SwiftUI and of any media framework:
/// it carries only what the import step can establish without decoding the file.
/// Metadata extraction and compatibility assessment belong to a later phase.
struct MediaFile: Identifiable, Equatable, Sendable {
    /// Stable identity for SwiftUI presentation.
    let id: UUID
    /// Location of the file on disk, as selected by the user.
    let url: URL
    /// File name including its extension, ready for display.
    let name: String
    /// Size of the file in bytes.
    let byteCount: Int64
    /// Container format inferred from the file name.
    let format: MediaFormat

    init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        byteCount: Int64,
        format: MediaFormat
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.byteCount = byteCount
        self.format = format
    }
}

/// Container format of an imported media file, inferred from its path extension.
struct MediaFormat: Equatable, Sendable {
    /// Lowercased path extension of the file, or `nil` when the name has none.
    let fileExtension: String?

    /// Label presented to the user, for example "MP4".
    var displayName: String {
        guard let fileExtension, !fileExtension.isEmpty else {
            return "Unknown format"
        }
        return fileExtension.uppercased()
    }
}
