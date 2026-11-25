import Foundation
import Testing
@testable import GoogleCastPlayer

struct CastMessageTests {
    @Test func encodesTheKnownFieldsInOrder() {
        let message = CastMessage(
            sourceID: "a",
            destinationID: "b",
            namespace: "n",
            payload: "p"
        )

        // protocol 0, source "a", destination "b", namespace "n", type 0, payload "p"
        let expected: [UInt8] = [
            0x08, 0x00,
            0x12, 0x01, 0x61,
            0x1A, 0x01, 0x62,
            0x22, 0x01, 0x6E,
            0x28, 0x00,
            0x32, 0x01, 0x70,
        ]
        #expect(Array(message.encoded()) == expected)
    }

    @Test func roundTripsARealMessage() throws {
        let message = CastMessage(
            sourceID: "sender-0",
            destinationID: "receiver-0",
            namespace: CastClient.Namespace.receiver,
            payload: #"{"type":"LAUNCH","appId":"CC1AD845","requestId":1}"#
        )

        let decoded = try #require(CastMessage.decode(message.encoded()))

        #expect(decoded == message)
    }

    @Test func prefixesTheFrameWithItsLength() {
        let message = CastMessage(sourceID: "a", destinationID: "b", namespace: "n", payload: "p")
        let framed = message.framed()
        let body = message.encoded()

        let declared = framed.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        #expect(declared == body.count)
        #expect(framed.dropFirst(4) == body)
    }

    @Test func splitsAStreamIntoCompleteFrames() {
        let first = CastMessage(sourceID: "a", destinationID: "b", namespace: "n", payload: "1")
        let second = CastMessage(sourceID: "a", destinationID: "b", namespace: "n", payload: "2")
        var stream = first.framed()
        stream.append(second.framed())
        stream.append(Data([0x00, 0x00]))

        let (messages, remainder) = CastMessage.frames(in: stream)

        #expect(messages == [first, second])
        #expect(remainder == Data([0x00, 0x00]))
    }

    @Test func ignoresUnknownFields() throws {
        var data = CastMessage(sourceID: "a", destinationID: "b", namespace: "n", payload: "p").encoded()
        data.append(contentsOf: [0x3A, 0x01, 0x78]) // field 7, length 1, "x"

        let decoded = try #require(CastMessage.decode(data))

        #expect(decoded.payload == "p")
    }

    @Test func rejectsTruncatedMessages() {
        #expect(CastMessage.decode(Data([0x12, 0x05, 0x61])) == nil)
        #expect(CastMessage.decode(Data([0x12])) == nil)
    }
}
