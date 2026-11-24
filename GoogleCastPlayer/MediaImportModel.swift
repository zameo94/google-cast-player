import Foundation
import Observation

/// Application state for the media import flow.
///
/// The model owns the selected file and the current import error. It performs no
/// presentation work, so it can be exercised by unit tests without a UI.
@MainActor
@Observable
final class MediaImportModel {
    /// The imported file, or `nil` while nothing is selected.
    private(set) var selectedFile: MediaFile?
    /// Message describing the last failed import, or `nil` when there is none.
    private(set) var errorMessage: String?

    private let importer: MediaImporter

    init(importer: MediaImporter = MediaImporter()) {
        self.importer = importer
    }

    /// Imports the file provided by a drop or by the file picker.
    ///
    /// A failed import keeps the previous selection and reports the problem
    /// through `errorMessage`.
    func importFiles(at urls: [URL]) {
        guard !urls.isEmpty else {
            return
        }
        guard urls.count == 1, let url = urls.first else {
            errorMessage = MediaImportError.multipleSelection.errorDescription
            return
        }

        do {
            selectedFile = try importer.importMediaFile(at: url)
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
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

    /// Clears the current selection.
    func removeSelection() {
        selectedFile = nil
    }

    /// Dismisses the current error message.
    func dismissError() {
        errorMessage = nil
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
