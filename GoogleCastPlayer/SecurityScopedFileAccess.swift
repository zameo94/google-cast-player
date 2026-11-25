import Foundation

/// Acquires and releases the access the app holds to the selected file.
///
/// The app keeps access only while a file is selected, so it can read the file and,
/// in later phases, serve it to a receiver.
protocol FileAccessControlling {
    /// Starts access to `url` and reports whether a security scope was opened.
    @discardableResult
    func startAccessing(_ url: URL) -> Bool

    /// Stops access previously started for `url`.
    func stopAccessing(_ url: URL)
}

/// File access backed by the system security scope of the URL.
///
/// Files chosen through the open panel or dropped by the user arrive with a security
/// scope that must be retained while the file is in use. The call reports `false`
/// when no scope applies, for example in an unsandboxed build, and the file stays
/// readable without further handling.
struct SecurityScopedFileAccess: FileAccessControlling {
    @discardableResult
    func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
