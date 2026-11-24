import Foundation
import UniformTypeIdentifiers

/// Validates a user-selected item and describes it as a `MediaFile`.
///
/// The importer answers one question for Phase 1: is this a readable movie file
/// that the application may present as the selected media? It does not decode the
/// container, extract metadata, or judge Cast compatibility.
struct MediaImporter: Sendable {
    private static let requiredResourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isReadableKey,
        .fileSizeKey,
        .contentTypeKey,
    ]

    /// Checks the item at `url` and returns its media description.
    ///
    /// - Throws: `MediaImportError` describing why the item cannot be used.
    func importMediaFile(at url: URL) throws -> MediaFile {
        guard url.isFileURL else {
            throw MediaImportError.notAFile
        }

        let resourceValues: URLResourceValues
        do {
            resourceValues = try url.resourceValues(forKeys: Self.requiredResourceKeys)
        } catch {
            throw Self.importError(for: url)
        }

        guard resourceValues.isRegularFile == true else {
            throw MediaImportError.notAFile
        }
        guard resourceValues.isReadable != false else {
            throw MediaImportError.unreadableFile(name: url.lastPathComponent)
        }

        let contentType = resourceValues.contentType
        guard let contentType, contentType.conforms(to: .movie) else {
            throw MediaImportError.unsupportedFileType(
                name: url.lastPathComponent,
                typeDescription: contentType?.localizedDescription
            )
        }

        return MediaFile(
            url: url,
            name: url.lastPathComponent,
            byteCount: Int64(resourceValues.fileSize ?? 0),
            format: MediaFormat(fileExtension: url.pathExtension.lowercased())
        )
    }

    private static func importError(for url: URL) -> MediaImportError {
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            return .unreadableFile(name: url.lastPathComponent)
        }
        return .fileNotFound
    }
}
