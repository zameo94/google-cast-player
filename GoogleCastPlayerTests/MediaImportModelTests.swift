import Foundation
import Testing
@testable import GoogleCastPlayer

@MainActor
struct MediaImportModelTests {
    @Test func importsFileAndClearsError() throws {
        let url = try TestFixture.file(named: "movie.mp4", contents: Data(count: 256))
        defer { TestFixture.remove(url) }
        let model = MediaImportModel(metadataExtractor: StubMetadataExtractor(result: .success(.targetProfile)))

        model.importFiles(at: [url])

        #expect(model.selectedFile?.name == "movie.mp4")
        #expect(model.selectedFile?.byteCount == 256)
        #expect(model.metadataState == .loading)
        #expect(model.errorMessage == nil)
    }

    @Test func emptyInputKeepsCurrentState() throws {
        let url = try TestFixture.file(named: "movie.mp4", contents: Data(count: 4))
        defer { TestFixture.remove(url) }
        let model = MediaImportModel(metadataExtractor: StubMetadataExtractor(result: .success(.targetProfile)))
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
        let model = MediaImportModel(metadataExtractor: StubMetadataExtractor(result: .success(.targetProfile)))
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
        let model = MediaImportModel(metadataExtractor: StubMetadataExtractor(result: .success(.targetProfile)))

        model.importFiles(at: [firstURL])
        model.importFiles(at: [secondURL])

        #expect(model.selectedFile?.name == "second.mov")
        #expect(model.selectedFile?.format == MediaFormat(fileExtension: "mov"))
        #expect(model.errorMessage == nil)
    }

    @Test func removeSelectionClearsTheFileAndMetadata() throws {
        let url = try TestFixture.file(named: "movie.mp4", contents: Data(count: 4))
        defer { TestFixture.remove(url) }
        let model = MediaImportModel(metadataExtractor: StubMetadataExtractor(result: .success(.targetProfile)))
        model.importFiles(at: [url])

        model.removeSelection()

        #expect(model.selectedFile == nil)
        #expect(model.metadataState == nil)
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

    // MARK: - File access lifetime

    @Test func holdsAccessToTheSelectedFile() throws {
        let url = try TestFixture.file(named: "movie.mp4", contents: Data(count: 4))
        defer { TestFixture.remove(url) }
        let access = FileAccessSpy()
        let model = MediaImportModel(fileAccess: access)

        model.importFiles(at: [url])

        #expect(access.startedURLs == [url])
        #expect(access.stoppedURLs.isEmpty)
    }

    @Test func releasesAccessWhenTheSelectionIsReplaced() throws {
        let firstURL = try TestFixture.file(named: "first.mp4", contents: Data(count: 4))
        defer { TestFixture.remove(firstURL) }
        let secondURL = try TestFixture.file(named: "second.mp4", contents: Data(count: 4))
        defer { TestFixture.remove(secondURL) }
        let access = FileAccessSpy()
        let model = MediaImportModel(fileAccess: access)

        model.importFiles(at: [firstURL])
        model.importFiles(at: [secondURL])

        #expect(access.startedURLs == [firstURL, secondURL])
        #expect(access.stoppedURLs == [firstURL])
    }

    @Test func releasesAccessWhenTheSelectionIsRemoved() throws {
        let url = try TestFixture.file(named: "movie.mp4", contents: Data(count: 4))
        defer { TestFixture.remove(url) }
        let access = FileAccessSpy()
        let model = MediaImportModel(fileAccess: access)
        model.importFiles(at: [url])

        model.removeSelection()

        #expect(access.stoppedURLs == [url])
    }

    @Test func doesNotReleaseAccessThatWasNeverGranted() throws {
        let firstURL = try TestFixture.file(named: "first.mp4", contents: Data(count: 4))
        defer { TestFixture.remove(firstURL) }
        let secondURL = try TestFixture.file(named: "second.mp4", contents: Data(count: 4))
        defer { TestFixture.remove(secondURL) }
        let access = FileAccessSpy()
        access.grantsAccess = false
        let model = MediaImportModel(fileAccess: access)

        model.importFiles(at: [firstURL])
        model.importFiles(at: [secondURL])
        model.removeSelection()

        #expect(access.startedURLs.count == 2)
        #expect(access.stoppedURLs.isEmpty)
    }

    @Test func keepsAccessWhenAnImportFails() throws {
        let validURL = try TestFixture.file(named: "movie.mp4", contents: Data(count: 4))
        defer { TestFixture.remove(validURL) }
        let invalidURL = try TestFixture.file(named: "notes.txt", contents: Data("text".utf8))
        defer { TestFixture.remove(invalidURL) }
        let access = FileAccessSpy()
        let model = MediaImportModel(fileAccess: access)
        model.importFiles(at: [validURL])

        model.importFiles(at: [invalidURL])

        #expect(access.stoppedURLs.isEmpty)
        #expect(model.selectedFile?.name == "movie.mp4")
    }

    // MARK: - Metadata

    @Test func publishesMetadataAndCompatibility() async throws {
        let url = try TestFixture.file(named: "movie.mp4", contents: Data(count: 8))
        defer { TestFixture.remove(url) }
        let model = MediaImportModel(metadataExtractor: StubMetadataExtractor(result: .success(.targetProfile)))
        model.importFiles(at: [url])

        await model.loadMetadata()

        guard case let .available(metadata, compatibility) = model.metadataState else {
            Issue.record("Expected available metadata, got \(String(describing: model.metadataState))")
            return
        }
        #expect(metadata == .targetProfile)
        #expect(compatibility.status == .compatible)
    }

    @Test func reportsMetadataThatCannotBeRead() async throws {
        let url = try TestFixture.file(named: "movie.mp4", contents: Data(count: 8))
        defer { TestFixture.remove(url) }
        let failure = MediaMetadataError.notReadable(name: "movie.mp4")
        let model = MediaImportModel(metadataExtractor: StubMetadataExtractor(result: .failure(failure)))
        model.importFiles(at: [url])

        await model.loadMetadata()

        #expect(model.metadataState == .unavailable(failure.errorDescription ?? ""))
        #expect(model.selectedFile?.name == "movie.mp4")
    }

    @Test func clearsMetadataWhenNothingIsSelected() async {
        let model = MediaImportModel()

        await model.loadMetadata()

        #expect(model.metadataState == nil)
    }

    @Test func discardsMetadataThatArrivesAfterTheSelectionChanged() async throws {
        let firstURL = try TestFixture.file(named: "first.mp4", contents: Data(count: 4))
        defer { TestFixture.remove(firstURL) }
        let secondURL = try TestFixture.file(named: "second.mp4", contents: Data(count: 4))
        defer { TestFixture.remove(secondURL) }
        let extractor = StalledMetadataExtractor(metadata: .targetProfile)
        let model = MediaImportModel(metadataExtractor: extractor)
        model.importFiles(at: [firstURL])

        let loadTask = Task { await model.loadMetadata() }
        await extractor.waitUntilExtractionStarts()
        model.importFiles(at: [secondURL])
        await extractor.releaseExtraction()
        await loadTask.value

        #expect(model.selectedFile?.name == "second.mp4")
        #expect(model.metadataState == .loading)
    }
}
