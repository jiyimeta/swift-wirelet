import Foundation
import Testing
@testable import Wirelet

@WireFormat
struct DataFieldBlob {
    var name: String
    var bytes: Data
}

@Test func dataFieldRoundTrip() throws {
    let original = DataFieldBlob(name: "hello", bytes: Data([0x01, 0x02, 0x03]))
    let decoded = try DataFieldBlob(decoding: original.encodeToData())
    #expect(decoded.name == "hello")
    #expect(decoded.bytes == Data([0x01, 0x02, 0x03]))
}

@Test func dataFieldEmptyRoundTrip() throws {
    let original = DataFieldBlob(name: "x", bytes: Data())
    let decoded = try DataFieldBlob(decoding: original.encodeToData())
    #expect(decoded.name == "x")
    #expect(decoded.bytes.isEmpty)
}

@Test func dataPayloadWireBytes() {
    // Just the payload encoding for a 3-byte Data:
    // varint(3) = 0x03, then 0x01 0x02 0x03 → [0x03, 0x01, 0x02, 0x03].
    var w = WireFormatWriter()
    Data([0x01, 0x02, 0x03]).encodePayload(into: &w)
    #expect(w.data == Data([0x03, 0x01, 0x02, 0x03]))
}

@Test func dataEmptyPayloadWireBytes() {
    var w = WireFormatWriter()
    Data().encodePayload(into: &w)
    // varint(0) = 0x00, no following bytes.
    #expect(w.data == Data([0x00]))
}

@Test func dataDecodesRawBytes() throws {
    // Manually constructed payload: length 4, then 0xDE 0xAD 0xBE 0xEF.
    let payload = Data([0x04, 0xDE, 0xAD, 0xBE, 0xEF])
    var r = WireFormatReader(data: payload)
    let decoded = try Data(decodingPayload: &r)
    #expect(decoded == Data([0xDE, 0xAD, 0xBE, 0xEF]))
    #expect(r.isAtEnd)
}
