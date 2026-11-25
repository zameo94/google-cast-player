import Foundation

/// The head of an HTTP/1.x request, as far as the media server needs it.
struct HTTPRequest: Equatable, Sendable {
    /// Method as sent by the client, for example `GET`.
    let method: String
    /// Request target, for example `/media/abc`.
    let path: String
    /// Header fields, with lowercased names. Repeated fields keep the first value.
    let headers: [String: String]

    /// Whether `data` already contains the end of the request head.
    static func isHeadComplete(_ data: Data) -> Bool {
        data.range(of: Data("\r\n\r\n".utf8)) != nil
    }

    /// Parses a complete request head, or returns `nil` when it is malformed.
    static func parse(_ data: Data) -> HTTPRequest? {
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/") else {
            return nil
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.isEmpty {
                break
            }
            guard let colon = line.firstIndex(of: ":") else {
                return nil
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                return nil
            }
            if headers[name] == nil {
                headers[name] = value
            }
        }

        return HTTPRequest(method: String(parts[0]), path: String(parts[1]), headers: headers)
    }
}
