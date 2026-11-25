import Foundation

/// A Cast V2 protocol message.
///
/// The protocol carries protobuf messages inside a length-prefixed frame. Only the
/// fields the app needs are modelled, and encoding/decoding is written by hand so the
/// project keeps no third-party dependency. Unknown fields are ignored on decode.
struct CastMessage: Equatable, Sendable {
    enum PayloadType: Int, Sendable {
        case string = 0
        case binary = 1
    }

    /// Identifier of the sender, for example `sender-0`.
    var sourceID: String
    /// Identifier of the recipient, for example `receiver-0` or a transport id.
    var destinationID: String
    /// Protocol namespace that defines the meaning of the payload.
    var namespace: String
    /// Encoding of the payload.
    var payloadType: PayloadType = .string
    /// UTF-8 JSON payload.
    var payload: String

    /// Encodes the message as protobuf bytes, without the length prefix.
    func encoded() -> Data {
        var writer = ProtobufWriter()
        writer.writeVarintField(1, UInt64(0)) // protocol version 0
        writer.writeStringField(2, sourceID)
        writer.writeStringField(3, destinationID)
        writer.writeStringField(4, namespace)
        writer.writeVarintField(5, UInt64(payloadType.rawValue))
        writer.writeStringField(6, payload)
        return writer.data
    }

    /// Encodes the message as a frame: big-endian length followed by the protobuf bytes.
    func framed() -> Data {
        let body = encoded()
        var frame = Data()
        var length = UInt32(body.count).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(body)
        return frame
    }

    /// Decodes protobuf bytes, or returns `nil` when the message is malformed.
    static func decode(_ data: Data) -> CastMessage? {
        var reader = ProtobufReader(data: data)
        var sourceID = ""
        var destinationID = ""
        var namespace = ""
        var payloadType = PayloadType.string
        var payload = ""

        while let field = reader.nextField() {
            switch field.number {
            case 2:
                guard let value = reader.readString() else { return nil }
                sourceID = value
            case 3:
                guard let value = reader.readString() else { return nil }
                destinationID = value
            case 4:
                guard let value = reader.readString() else { return nil }
                namespace = value
            case 5:
                guard let value = reader.readVarint(), let type = PayloadType(rawValue: Int(value)) else {
                    return nil
                }
                payloadType = type
            case 6:
                guard let value = reader.readString() else { return nil }
                payload = value
            default:
                guard reader.skipField(field) else { return nil }
            }
        }

        return CastMessage(
            sourceID: sourceID,
            destinationID: destinationID,
            namespace: namespace,
            payloadType: payloadType,
            payload: payload
        )
    }

    /// Splits a byte stream into complete frames, returning the leftover bytes.
    static func frames(in buffer: Data) -> (messages: [CastMessage], remainder: Data) {
        let bytes = [UInt8](buffer)
        var messages: [CastMessage] = []
        var offset = 0

        while bytes.count - offset >= 4 {
            let length = (Int(bytes[offset]) << 24)
                | (Int(bytes[offset + 1]) << 16)
                | (Int(bytes[offset + 2]) << 8)
                | Int(bytes[offset + 3])
            guard bytes.count - offset - 4 >= length else {
                break
            }
            let body = Data(bytes[(offset + 4)..<(offset + 4 + length)])
            if let message = decode(body) {
                messages.append(message)
            }
            offset += 4 + length
        }

        return (messages, Data(bytes[offset...]))
    }
}

// MARK: - Protobuf primitives

private struct ProtobufWriter {
    private(set) var data = Data()

    mutating func writeVarintField(_ number: Int, _ value: UInt64) {
        writeVarint(UInt64(number << 3))
        writeVarint(value)
    }

    mutating func writeStringField(_ number: Int, _ value: String) {
        let bytes = Data(value.utf8)
        writeVarint(UInt64((number << 3) | 2))
        writeVarint(UInt64(bytes.count))
        data.append(bytes)
    }

    private mutating func writeVarint(_ value: UInt64) {
        var remaining = value
        repeat {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 {
                byte |= 0x80
            }
            data.append(byte)
        } while remaining != 0
    }
}

private struct ProtobufReader {
    struct Field {
        let number: Int
        let wireType: Int
    }

    private let data: Data
    private var index: Data.Index
    private var remainingVarint: UInt64?

    init(data: Data) {
        self.data = data
        self.index = data.startIndex
    }

    mutating func nextField() -> Field? {
        guard remainingVarint == nil else {
            return nil
        }
        guard let key = readVarint() else {
            return nil
        }
        return Field(number: Int(key >> 3), wireType: Int(key & 0x7))
    }

    mutating func readVarint() -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < data.endIndex, shift < 64 {
            let byte = data[index]
            index = data.index(after: index)
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
        }
        return nil
    }

    mutating func readString() -> String? {
        guard let length = readVarint(), length <= UInt64(data.endIndex - index) else {
            return nil
        }
        let end = data.index(index, offsetBy: Int(length))
        defer { index = end }
        return String(data: data[index..<end], encoding: .utf8)
    }

    mutating func skipField(_ field: Field) -> Bool {
        switch field.wireType {
        case 0:
            return readVarint() != nil
        case 2:
            return readString() != nil
        default:
            return false
        }
    }
}
