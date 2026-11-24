import Foundation

/// Reasons an imported item cannot be used as the selected media file.
///
/// Every case carries a message suitable for direct presentation, so the UI can
/// report the problem without interpreting the error itself.
enum MediaImportError: Error, Equatable, LocalizedError {
    /// The item exists but is not a regular file, for example a folder.
    case notAFile
    /// Nothing exists at the selected location.
    case fileNotFound
    /// The file exists but its contents cannot be read.
    case unreadableFile(name: String)
    /// The file type is not a movie format macOS recognizes.
    case unsupportedFileType(name: String, typeDescription: String?)
    /// More than one item was provided where a single video is expected.
    case multipleSelection

    var errorDescription: String? {
        switch self {
        case .notAFile:
            return "The selected item is not a file. Choose a video file."
        case .fileNotFound:
            return "The selected file could not be found. It may have been moved or deleted."
        case let .unreadableFile(name):
            return "\u{201C}\(name)\u{201D} cannot be read. Check its permissions or choose another file."
        case let .unsupportedFileType(name, typeDescription):
            let typeName = typeDescription ?? "unknown type"
            return "\u{201C}\(name)\u{201D} is not a supported video file (\(typeName)). Choose a movie file such as MP4 or MOV."
        case .multipleSelection:
            return "Choose one video file at a time."
        }
    }
}
