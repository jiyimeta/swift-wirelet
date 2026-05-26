import Testing
import Foundation
@testable import Wirelet

@WireFormat
struct NestedInner {
    var a: Int32
    var b: Int32
}

@WireFormat
struct NestedOuter {
    var inner: NestedInner
    var c: Int32
}

@WireFormat
struct NestedArrayOuter {
    var items: [NestedInner]
    var c: Int32
}

@Test func nestedStructRoundTrip() throws {
    let v = NestedOuter(inner: NestedInner(a: 1, b: 2), c: 3)
    let data = v.encodeToData()
    let decoded = try NestedOuter(decoding: data)
    #expect(decoded.inner.a == 1)
    #expect(decoded.inner.b == 2)
    #expect(decoded.c == 3)
}

@Test func nestedStructArrayRoundTrip() throws {
    let v = NestedArrayOuter(
        items: [NestedInner(a: 1, b: 2), NestedInner(a: 3, b: 4)],
        c: 99,
    )
    let data = v.encodeToData()
    let decoded = try NestedArrayOuter(decoding: data)
    #expect(decoded.items.count == 2)
    #expect(decoded.items[0].a == 1)
    #expect(decoded.items[0].b == 2)
    #expect(decoded.items[1].a == 3)
    #expect(decoded.items[1].b == 4)
    #expect(decoded.c == 99)
}
