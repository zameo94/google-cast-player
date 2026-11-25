import Foundation
import Observation

/// Application state for the media import flow.
///
/// The model owns the selected file, the access held to it and the description read
/// from it. It performs no presentation work, so unit tests exercise it without a UI.
@MainActor
@Observable
final class MediaImportModel {
    /// What the app knows about the metadata of the selected file.
    enum MetadataState: Equatable {
        /// Metadata is being read.
        case loading
        /// Metadata was read and judged against the playback profile.
        case available(MediaMetadata, MediaCompatibility)
        /// Metadata could not be read; the message is ready for display.
        case unavailable(String)
    }

    /// The imported file, or `nil` while nothing is selected.
    private(set) var selectedFile: MediaFile?
    /// Message describing the last failed import, or `nil` when there is none.
    private(set) var errorMessage: String?
    /// Metadata of the selected file, or `nil` while nothing is selected.
    private(set) var metadataState: MetadataState?

    private let importer: MediaImporter
    private let metadataExtractor: any MediaMetadataExtracting
    private let compatibilityEvaluator: MediaCompatibilityEvaluator
    private let fileAccess: any FileAccessControlling
    private var scopeRetainedForURL: URL?

    init(
        importer: MediaImporter = MediaImporter(),
        metadataExtractor: any MediaMetadataExtracting = MediaMetadataExtractor(),
        compatibilityEvaluator: MediaCompatibilityEvaluator = MediaCompatibilityEvaluator(),
        fileAccess: any FileAccessControlling = SecurityScopedFileAccess()
    ) {
        self.importer = importer
        self.metadataExtractor = metadataExtractor
        self.compatibilityEvaluator = compatibilityEvaluator
        self.fileAccess = fileAccess
    }

    /// Imports the file provided by a drop or by the file picker.
    ///
    /// A failed import keeps the previous selection and reports the problem through
    /// `errorMessage`. A successful import holds access to the new file and leaves
    /// metadata in the `loading` state for `loadMetadata()`.
    func importFiles(at urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }
        guard urls.count == 1, let url = urls.first else {
            errorMessage = MediaImportError.multipleSelection.errorDescription
            return
        }

        let mediaFile: MediaFile
        do {
            mediaFile = try importer.importMediaFile(at: url)
        } catch {
            errorMessage = Self.message(for: error)
            return
        }

        releaseAccess()
        if fileAccess.startAccessing(mediaFile.url) {
            scopeRetainedForURL = mediaFile.url
        }
        selectedFile = mediaFile
        metadataState = .loading
        errorMessage = nil
    }

    /// Reads the metadata of the selected file and judges its compatibility.
    ///
    /// A selection replaced while the read is in flight wins: the late result is
    /// discarded instead of describing the wrong file.
    func loadMetadata() async {
        guard let mediaFile = selectedFile else {
            metadataState = nil
            return
        }

        do {
            let metadata = try await metadataExtractor.extractMetadata(from: mediaFile.url)
            guard selectedFile?.id == mediaFile.id else {
                return
            }
            metadataState = .available(
                metadata,
                compatibilityEvaluator.assess(metadata: metadata, format: mediaFile.format)
            )
        } catch {
            guard selectedFile?.id == mediaFile.id else {
                return
            }
            metadataState = .unavailable(Self.message(for: error))
        }
    }

    /// Reports a failure raised by the file picker itself.
    ///
    /// User cancellation is not an error and keeps the current state untouched.
    func reportFilePickerFailure(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
            return
        }
        errorMessage = Self.message(for: error)
    }

    /// Clears the current selection and releases its access.
    func removeSelection() {
        releaseAccess()
        selectedFile = nil
        metadataState = nil
    }

    /// Dismisses the current error message.
    func dismissError() {
        errorMessage = nil
    }

    private func releaseAccess() {
        if let scopeRetainedForURL {
            fileAccess.stopAccessing(scopeRetainedForURL)
        }
        scopeRetainedForURL = nil
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
