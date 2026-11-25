import Foundation
import Testing
@testable import GoogleCastPlayer

struct HTTPRequestTests {
    private func request(_ text: String) -> HTTPRequest? {
        HTTPRequest.parse(Data(text.utf8))
    }

    @Test func parsesAGetRequest() throws {
        let parsed = try #require(request("GET /media/abc HTTP/1.1\r\nHost: 127.0.0.1\r\nRange: bytes=0-9\r\n\r\n"))

        #expect(parsed.method == "GET")
        #expect(parsed.path == "/media/abc")
        #expect(parsed.headers["host"] == "127.0.0.1")
        #expect(parsed.headers["range"] == "bytes=0-9")
    }

    @Test func lowercasesHeaderNames() throws {
        let parsed = try #require(request("HEAD /x HTTP/1.1\r\nRANGE: bytes=5-\r\n\r\n"))

        #expect(parsed.headers["range"] == "bytes=5-")
    }

    @Test func keepsTheFirstValueOfARepeatedHeader() throws {
        let parsed = try #require(request("GET /x HTTP/1.1\r\nRange: bytes=0-1\r\nRange: bytes=5-6\r\n\r\n"))

        #expect(parsed.headers["range"] == "bytes=0-1")
    }

    @Test func rejectsMalformedRequests() {
        #expect(request("not a request line\r\n\r\n") == nil)
        #expect(request("GET /x\r\n\r\n") == nil)
        #expect(request("GET /x HTTP/1.1\r\nBroken header\r\n\r\n") == nil)
        #expect(request("GET /x HTTP/1.1\r\n: empty\r\n\r\n") == nil)
    }

    @Test func detectsACompleteRequestHead() {
        #expect(HTTPRequest.isHeadComplete(Data("GET / HTTP/1.1\r\n\r\n".utf8)))
        #expect(!HTTPRequest.isHeadComplete(Data("GET / HTTP/1.1\r\n".utf8)))
        #expect(!HTTPRequest.isHeadComplete(Data()))
    }
}
