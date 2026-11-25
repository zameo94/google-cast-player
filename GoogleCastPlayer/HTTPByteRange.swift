import Foundation

/// A concrete byte range of a resource, with an inclusive end index.
struct HTTPByteRange: Equatable, Sendable {
    let start: Int64
    let end: Int64

    /// Number of bytes the range covers.
    var length: Int64 {
        end - start + 1
    }

    /// Result of interpreting a `Range` request header.
    enum Resolution: Equatable, Sendable {
        /// Serve the whole resource.
        case complete
        /// Serve the requested bytes.
        case partial(HTTPByteRange)
        /// The requested range cannot exist for this resource size.
        case unsatisfiable
    }

    /// Interprets a `Range` header for a resource of `size` bytes.
    ///
    /// Only a single range is supported. A header that cannot be understood, or one
    /// that asks for several ranges, is ignored and the complete resource is served,
    /// which RFC 9110 allows. A range that starts beyond the resource is reported as
    /// unsatisfiable so the caller can answer 416.
    static func resolve(header: String?, size: Int64) -> Resolution {
        guard let header else {
            return .complete
        }
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("bytes=") else {
            return .complete
        }
        let specifier = String(trimmed.dropFirst("bytes=".count))
        guard !specifier.contains(",") else {
            return .complete
        }

        let parts = specifier.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return .complete
        }
        let startText = parts[0].trimmingCharacters(in: .whitespaces)
        let endText = parts[1].trimmingCharacters(in: .whitespaces)

        if startText.isEmpty {
            return resolveSuffix(bytes: endText, size: size)
        }

        guard let start = Int64(startText), start >= 0 else {
            return .complete
        }
        guard start < size else {
            return .unsatisfiable
        }
        if endText.isEmpty {
            return .partial(HTTPByteRange(start: start, end: size - 1))
        }
        guard let requestedEnd = Int64(endText), requestedEnd >= start else {
            return .complete
        }
        return .partial(HTTPByteRange(start: start, end: min(requestedEnd, size - 1)))
    }

    private static func resolveSuffix(bytes text: String, size: Int64) -> Resolution {
        guard let suffixLength = Int64(text), suffixLength > 0 else {
            return .complete
        }
        guard size > 0 else {
            return .unsatisfiable
        }
        return .partial(HTTPByteRange(start: max(0, size - suffixLength), end: size - 1))
    }
}
