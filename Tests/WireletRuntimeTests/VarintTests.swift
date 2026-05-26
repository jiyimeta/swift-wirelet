import Testing
import Foundation
@testable import Wirelet

@Test func unsignedVarintRoundTrip() throws {
    let cases: [UInt64] = [0, 1, 127, 128, 16383, 16384, UInt64.max]
    for v in cases {
        var w = WireFormatWriter()
        w.writeVarint(v)
        var r = WireFormatReader(data: w.data)
        try #expect(r.readVarint() == v)
    }
}

@Test func zigZagSignedRoundTrip() throws {
    let cases: [Int64] = [0, -1, 1, -2, 2, Int64.min, Int64.max]
    for v in cases {
        var w = WireFormatWriter()
        w.writeZigZagVarint(v)
        var r = WireFormatReader(data: w.data)
        try #expect(r.readZigZagVarint() == v)
    }
}

@Test func varintOverflowDetected() {
    // 11 bytes of continuation = guaranteed overflow.
    let bytes = Data(repeating: 0x80, count: 11)
    var r = WireFormatReader(data: bytes)
    #expect(throws: WireFormatError.varintOverflow) { try r.readVarint() }
}
