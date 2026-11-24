import Foundation

/// Temporary fixtures for the media import tests.
///
/// Each fixture lives in its own temporary directory outside the repository, so a
/// test run never leaves artifacts in the working tree.
enum TestFixture {
    /// Creates a file with the given name and contents.
    static func file(named name: String, contents: Data) throws -> URL {
        let directory = try makeDirectory()
        let url = directory.appending(path: name)
        try contents.write(to: url)
        return url
    }

    /// Creates a directory with the given name.
    static func directory(named name: String) throws -> URL {
        let parent = try makeDirectory()
        let url = parent.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    /// Location of a file that never existed on disk.
    static func missingFileURL(named name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "GoogleCastPlayerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: name)
    }

    /// Removes the fixture, restoring permissions first when a test changed them.
    static func remove(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path(percentEncoded: false)
        )
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    private static func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "GoogleCastPlayerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}
