import os

/// Local diagnostics for the cast lifecycle.
///
/// The application writes nothing to the unified log by default, so a session that ends
/// hours after it started cannot be explained afterwards. These loggers cover what
/// started, what ended it and why; they never log the media URL, which carries the
/// per-session token.
enum CastLog {
    private static let subsystem = "io.github.zameo94.GoogleCastPlayer"

    static let playback = Logger(subsystem: subsystem, category: "playback")
    static let connection = Logger(subsystem: subsystem, category: "connection")
    static let client = Logger(subsystem: subsystem, category: "client")
    static let server = Logger(subsystem: subsystem, category: "server")
}
