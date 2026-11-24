import Foundation
import Testing
@testable import GoogleCastPlayer

struct MediaImporterTests {
    private let importer = MediaImporter()

    @Test func importsReadableMovieFile() throws {
        let contents = Data(repeating: 0x2A, count: 4096)
        let url = try TestFixture.file(named: "clip.mp4", contents: contents)
        defer { TestFixture.remove(url) }

        let mediaFile = try importer.importMediaFile(at: url)

        #expect(mediaFile.url == url)
        #expect(mediaFile.name == "clip.mp4")
        #expect(mediaFile.byteCount == 4096)
        #expect(mediaFile.format == MediaFormat(fileExtension: "mp4"))
        #expect(mediaFile.format.displayName == "MP4")
    }

    @Test func lowercasesTheExtensionForDisplay() throws {
        let url = try TestFixture.file(named: "Holiday.MP4", contents: Data(count: 16))
        defer { TestFixture.remove(url) }

        let mediaFile = try importer.importMediaFile(at: url)

        #expect(mediaFile.format == MediaFormat(fileExtension: "mp4"))
        #expect(mediaFile.format.displayName == "MP4")
        #expect(mediaFile.byteCount == 16)
    }

    @Test func rejectsMissingFile() {
        let url = TestFixture.missingFileURL(named: "missing.mp4")

        #expect(throws: MediaImportError.fileNotFound) {
            try importer.importMediaFile(at: url)
        }
    }

    @Test func rejectsDirectory() throws {
        let url = try TestFixture.directory(named: "folder.mp4")
        defer { TestFixture.remove(url) }

        #expect(throws: MediaImportError.notAFile) {
            try importer.importMediaFile(at: url)
        }
    }

    @Test func rejectsNonFileURL() throws {
        let url = try #require(URL(string: "https://example.com/clip.mp4"))

        #expect(throws: MediaImportError.notAFile) {
            try importer.importMediaFile(at: url)
        }
    }

    @Test func rejectsFileThatIsNotAMovie() throws {
        let url = try TestFixture.file(named: "notes.txt", contents: Data("plain text".utf8))
        defer { TestFixture.remove(url) }

        #expect {
            try importer.importMediaFile(at: url)
        } throws: { error in
            guard case let MediaImportError.unsupportedFileType(name, _) = error else {
                return false
            }
            return name == "notes.txt"
        }
    }

    @Test func rejectsUnreadableFile() throws {
        try #require(geteuid() != 0, "Permission checks are bypassed when tests run as root")

        let url = try TestFixture.file(named: "locked.mp4", contents: Data(count: 8))
        defer { TestFixture.remove(url) }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000],
            ofItemAtPath: url.path(percentEncoded: false)
        )

        #expect {
            try importer.importMediaFile(at: url)
        } throws: { error in
            guard case let MediaImportError.unreadableFile(name) = error else {
                return false
            }
            return name == "locked.mp4"
        }
    }
}
