import Foundation
import Testing
@testable import GoogleCastPlayer

struct HTTPByteRangeTests {
    @Test func servesTheWholeResourceWithoutARangeHeader() {
        #expect(HTTPByteRange.resolve(header: nil, size: 1000) == .complete)
    }

    @Test func resolvesAClosedRange() {
        #expect(HTTPByteRange.resolve(header: "bytes=0-99", size: 1000) == .partial(HTTPByteRange(start: 0, end: 99)))
    }

    @Test func resolvesAnOpenEndedRange() {
        #expect(HTTPByteRange.resolve(header: "bytes=500-", size: 1000) == .partial(HTTPByteRange(start: 500, end: 999)))
    }

    @Test func resolvesASuffixRange() {
        #expect(HTTPByteRange.resolve(header: "bytes=-100", size: 1000) == .partial(HTTPByteRange(start: 900, end: 999)))
    }

    @Test func clampsTheEndToTheResourceSize() {
        #expect(HTTPByteRange.resolve(header: "bytes=900-5000", size: 1000) == .partial(HTTPByteRange(start: 900, end: 999)))
    }

    @Test func clampsASuffixLargerThanTheResource() {
        #expect(HTTPByteRange.resolve(header: "bytes=-5000", size: 1000) == .partial(HTTPByteRange(start: 0, end: 999)))
    }

    @Test func reportsRangesBeyondTheResourceAsUnsatisfiable() {
        #expect(HTTPByteRange.resolve(header: "bytes=1000-", size: 1000) == .unsatisfiable)
        #expect(HTTPByteRange.resolve(header: "bytes=2000-3000", size: 1000) == .unsatisfiable)
        #expect(HTTPByteRange.resolve(header: "bytes=0-", size: 0) == .unsatisfiable)
    }

    @Test func ignoresHeadersItCannotUnderstand() {
        #expect(HTTPByteRange.resolve(header: "items=0-5", size: 1000) == .complete)
        #expect(HTTPByteRange.resolve(header: "bytes=abc-def", size: 1000) == .complete)
        #expect(HTTPByteRange.resolve(header: "bytes=50-10", size: 1000) == .complete)
        #expect(HTTPByteRange.resolve(header: "bytes=-0", size: 1000) == .complete)
    }

    @Test func ignoresMultipleRangesAsAWhole() {
        #expect(HTTPByteRange.resolve(header: "bytes=0-99,200-299", size: 1000) == .complete)
    }

    @Test func toleratesSurroundingWhitespace() {
        #expect(HTTPByteRange.resolve(header: " bytes=10-19 ", size: 1000) == .partial(HTTPByteRange(start: 10, end: 19)))
    }

    @Test func reportsTheRangeLength() {
        #expect(HTTPByteRange(start: 10, end: 19).length == 10)
        #expect(HTTPByteRange(start: 0, end: 0).length == 1)
    }
}
