import Foundation
import Testing
@testable import GoogleCastPlayer

@MainActor
struct MediaImportModelTests {
    @Test func importsFileAndClearsError() throws {
        let url = try TestFixture.file(named: "movie.mp4", contents: Data(count: 256))
        defer { TestFixture.remove(url) }
        let model = MediaImportModel()

        model.importFiles(at: [url])

        #expect(model.selectedFile?.name == "movie.mp4")
        #expect(model.selectedFile?.byteCount == 256)
        #expect(model.errorMessage == nil)
    }

    @Test func emptyInputKeepsCurrentState() throws {
        let url = try TestFixture.file(named: "movie.mp4", contents: Data(count: 4))
        defer { TestFixture.remove(url) }
        let model = MediaImportModel()
        model.importFiles(at: [url])

        model.importFiles(at: [])

        #expect(model.selectedFile?.name == "movie.mp4")
        #expect(model.errorMessage == nil)
    }

    @Test func rejectsMultipleFiles() {
        let model = MediaImportModel()

        model.importFiles(at: [
            TestFixture.missingFileURL(named: "first.mp4"),
            TestFixture.missingFileURL(named: "second.mp4"),
        ])

        #expect(model.selectedFile == nil)
        #expect(model.errorMessage == MediaImportError.multipleSelection.errorDescription)
    }

    @Test func keepsPreviousSelectionWhenImportFails() throws {
        let validURL = try TestFixture.file(named: "movie.mp4", contents: Data(count: 32))
        defer { TestFixture.remove(validURL) }
        let invalidURL = try TestFixture.file(named: "notes.txt", contents: Data("text".utf8))
        defer { TestFixture.remove(invalidURL) }
        let model = MediaImportModel()
        model.importFiles(at: [validURL])

        model.importFiles(at: [invalidURL])

        #expect(model.selectedFile?.name == "movie.mp4")
        #expect(model.errorMessage != nil)
    }

    @Test func replacesSelectionWithTheNewFile() throws {
        let firstURL = try TestFixture.file(named: "first.mp4", contents: Data(count: 8))
        defer { TestFixture.remove(firstURL) }
        let secondURL = try TestFixture.file(named: "second.mov", contents: Data(count: 16))
        defer { TestFixture.remove(secondURL) }
        let model = MediaImportModel()

        model.importFiles(at: [firstURL])
        model.importFiles(at: [secondURL])

        #expect(model.selectedFile?.name == "second.mov")
        #expect(model.selectedFile?.format == MediaFormat(fileExtension: "mov"))
        #expect(model.errorMessage == nil)
    }

    @Test func removeSelectionClearsTheFile() throws {
        let url = try TestFixture.file(named: "movie.mp4", contents: Data(count: 4))
        defer { TestFixture.remove(url) }
        let model = MediaImportModel()
        model.importFiles(at: [url])

        model.removeSelection()

        #expect(model.selectedFile == nil)
    }

    @Test func dismissErrorClearsTheMessage() throws {
        let model = MediaImportModel()
        model.importFiles(at: [TestFixture.missingFileURL(named: "missing.mp4")])
        try #require(model.errorMessage != nil)

        model.dismissError()

        #expect(model.errorMessage == nil)
    }

    @Test func pickerCancellationIsNotReportedAsAnError() {
        let model = MediaImportModel()

        model.reportFilePickerFailure(CocoaError(.userCancelled))

        #expect(model.errorMessage == nil)
    }

    @Test func pickerFailureIsReported() {
        let model = MediaImportModel()

        model.reportFilePickerFailure(MediaImportError.multipleSelection)

        #expect(model.errorMessage == MediaImportError.multipleSelection.errorDescription)
    }
}
