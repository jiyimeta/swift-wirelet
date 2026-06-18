import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import WireletMacros
import XCTest

private let fieldTestMacros: [String: Macro.Type] = [
    "WireFormat": WireFormatMacro.self,
    "WireFormatField": WireFormatFieldMacro.self,
]

private let explicitTagOnSingleFieldInput = """
@WireFormat
struct Foo {
    @WireFormatField(tag: 7) var x: Int32
}
"""

private let explicitTagOnSingleFieldExpanded = """
struct Foo {
    var x: Int32
}

extension Foo: WireFormatEncodable, WireFormatDecodable {
    public static var wireType: WireType {
        .lengthDelimited
    }

    public func encodePayload(into writer: inout WireFormatWriter) {
        writer.writeTag(tag: 7, wireType: Int32.wireType)
        x.encode(into: &writer)
    }

    public func encode(into writer: inout WireFormatWriter) {
        writer.writeLengthPrefixed { inner in
            encodePayload(into: &inner)
        }
    }

    public init(decodingPayload reader: inout WireFormatReader) throws {
        var _x: Int32? = nil
        while !reader.isAtEnd {
            let (tag, wt) = try reader.readTag()
            switch tag {
            case 7:
                _x = try Int32(from: &reader)
            default:
                try reader.skipUnknownField(wireType: wt)
            }
        }
        guard let _x else {
            throw WireFormatError.unknownTag(tag: 7, wireType: Int32.wireType)
        }
        self.x = _x
    }

    public init(from reader: inout WireFormatReader) throws {
        let len = Int(try reader.readVarint())
        let slice = try reader.readBytes(count: len)
        var inner = WireFormatReader(data: slice)
        try self.init(decodingPayload: &inner)
    }
}
"""

private let implicitTagSkipsExplicitInput = """
@WireFormat
struct Foo {
    var a: Int32
    @WireFormatField(tag: 7) var b: Int32
    var c: Int32
}
"""

private let implicitTagSkipsExplicitExpanded = """
struct Foo {
    var a: Int32
    var b: Int32
    var c: Int32
}

extension Foo: WireFormatEncodable, WireFormatDecodable {
    public static var wireType: WireType {
        .lengthDelimited
    }

    public func encodePayload(into writer: inout WireFormatWriter) {
        writer.writeTag(tag: 1, wireType: Int32.wireType)
        a.encode(into: &writer)
        writer.writeTag(tag: 7, wireType: Int32.wireType)
        b.encode(into: &writer)
        writer.writeTag(tag: 2, wireType: Int32.wireType)
        c.encode(into: &writer)
    }

    public func encode(into writer: inout WireFormatWriter) {
        writer.writeLengthPrefixed { inner in
            encodePayload(into: &inner)
        }
    }

    public init(decodingPayload reader: inout WireFormatReader) throws {
        var _a: Int32? = nil
        var _b: Int32? = nil
        var _c: Int32? = nil
        while !reader.isAtEnd {
            let (tag, wt) = try reader.readTag()
            switch tag {
            case 1:
                _a = try Int32(from: &reader)
            case 7:
                _b = try Int32(from: &reader)
            case 2:
                _c = try Int32(from: &reader)
            default:
                try reader.skipUnknownField(wireType: wt)
            }
        }
        guard let _a else {
            throw WireFormatError.unknownTag(tag: 1, wireType: Int32.wireType)
        }
        self.a = _a
        guard let _b else {
            throw WireFormatError.unknownTag(tag: 7, wireType: Int32.wireType)
        }
        self.b = _b
        guard let _c else {
            throw WireFormatError.unknownTag(tag: 2, wireType: Int32.wireType)
        }
        self.c = _c
    }

    public init(from reader: inout WireFormatReader) throws {
        let len = Int(try reader.readVarint())
        let slice = try reader.readBytes(count: len)
        var inner = WireFormatReader(data: slice)
        try self.init(decodingPayload: &inner)
    }
}
"""

private let reservedTagsSkippedByImplicitInput = """
@WireFormat(reservedTags: [1, 2])
struct Foo {
    var a: Int32
    var b: Int32
}
"""

private let reservedTagsSkippedByImplicitExpanded = """
struct Foo {
    var a: Int32
    var b: Int32
}

extension Foo: WireFormatEncodable, WireFormatDecodable {
    public static var wireType: WireType {
        .lengthDelimited
    }

    public func encodePayload(into writer: inout WireFormatWriter) {
        writer.writeTag(tag: 3, wireType: Int32.wireType)
        a.encode(into: &writer)
        writer.writeTag(tag: 4, wireType: Int32.wireType)
        b.encode(into: &writer)
    }

    public func encode(into writer: inout WireFormatWriter) {
        writer.writeLengthPrefixed { inner in
            encodePayload(into: &inner)
        }
    }

    public init(decodingPayload reader: inout WireFormatReader) throws {
        var _a: Int32? = nil
        var _b: Int32? = nil
        while !reader.isAtEnd {
            let (tag, wt) = try reader.readTag()
            switch tag {
            case 3:
                _a = try Int32(from: &reader)
            case 4:
                _b = try Int32(from: &reader)
            default:
                try reader.skipUnknownField(wireType: wt)
            }
        }
        guard let _a else {
            throw WireFormatError.unknownTag(tag: 3, wireType: Int32.wireType)
        }
        self.a = _a
        guard let _b else {
            throw WireFormatError.unknownTag(tag: 4, wireType: Int32.wireType)
        }
        self.b = _b
    }

    public init(from reader: inout WireFormatReader) throws {
        let len = Int(try reader.readVarint())
        let slice = try reader.readBytes(count: len)
        var inner = WireFormatReader(data: slice)
        try self.init(decodingPayload: &inner)
    }
}
"""

final class WireFormatFieldMacroExpansionTests: XCTestCase {
    // MARK: - Successful expansions

    func testExplicitTagOnSingleField() {
        assertMacroExpansion(
            explicitTagOnSingleFieldInput,
            expandedSource: explicitTagOnSingleFieldExpanded,
            macros: fieldTestMacros,
        )
    }

    func testImplicitTagSkipsExplicit() {
        // 3 properties: implicit a (1), explicit b (7), implicit c (counter advances to 2 then 3 ... so c == 2).
        // Per algorithm: counter resumes at next-unused, skipping seenExplicit. So a=1, b=7, c=2.
        assertMacroExpansion(
            implicitTagSkipsExplicitInput,
            expandedSource: implicitTagSkipsExplicitExpanded,
            macros: fieldTestMacros,
        )
    }

    func testReservedTagsSkippedByImplicit() {
        // Reserved {1, 2}. Two implicit fields land at 3 and 4.
        assertMacroExpansion(
            reservedTagsSkippedByImplicitInput,
            expandedSource: reservedTagsSkippedByImplicitExpanded,
            macros: fieldTestMacros,
        )
    }
}
