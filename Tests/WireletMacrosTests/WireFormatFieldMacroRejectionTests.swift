import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import WireletMacros
import XCTest

private let fieldTestMacros: [String: Macro.Type] = [
    "WireFormat": WireFormatMacro.self,
    "WireFormatField": WireFormatFieldMacro.self,
]

private let reservedTagRejectedInput = """
@WireFormat(reservedTags: [3])
struct Foo {
    @WireFormatField(tag: 3) var name: String
}
"""

private let reservedTagRejectedExpanded = """
struct Foo {
    var name: String
}

extension Foo: WireFormatEncodable, WireFormatDecodable {
    public static var wireType: WireType {
        .lengthDelimited
    }

    public func encodePayload(into writer: inout WireFormatWriter) {
        writer.writeTag(tag: 3, wireType: String.wireType)
        name.encode(into: &writer)
    }

    public func encode(into writer: inout WireFormatWriter) {
        writer.writeLengthPrefixed { inner in
            encodePayload(into: &inner)
        }
    }

    public init(decodingPayload reader: inout WireFormatReader) throws {
        var _name: String? = nil
        while !reader.isAtEnd {
            let (tag, wt) = try reader.readTag()
            switch tag {
            case 3:
                _name = try String(from: &reader)
            default:
                try reader.skipUnknownField(wireType: wt)
            }
        }
        guard let _name else {
            throw WireFormatError.unknownTag(tag: 3, wireType: String.wireType)
        }
        self.name = _name
    }

    public init(from reader: inout WireFormatReader) throws {
        let len = Int(try reader.readVarint())
        let slice = try reader.readBytes(count: len)
        var inner = WireFormatReader(data: slice)
        try self.init(decodingPayload: &inner)
    }
}
"""

private let tagConflictRejectedInput = """
@WireFormat
struct Foo {
    @WireFormatField(tag: 5) var a: Int32
    @WireFormatField(tag: 5) var b: Int32
}
"""

private let tagConflictRejectedExpanded = """
struct Foo {
    var a: Int32
    var b: Int32
}

extension Foo: WireFormatEncodable, WireFormatDecodable {
    public static var wireType: WireType {
        .lengthDelimited
    }

    public func encodePayload(into writer: inout WireFormatWriter) {
        writer.writeTag(tag: 5, wireType: Int32.wireType)
        a.encode(into: &writer)
        writer.writeTag(tag: 5, wireType: Int32.wireType)
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
            case 5:
                _a = try Int32(from: &reader)
            case 5:
                _b = try Int32(from: &reader)
            default:
                try reader.skipUnknownField(wireType: wt)
            }
        }
        guard let _a else {
            throw WireFormatError.unknownTag(tag: 5, wireType: Int32.wireType)
        }
        self.a = _a
        guard let _b else {
            throw WireFormatError.unknownTag(tag: 5, wireType: Int32.wireType)
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

private let zeroTagRejectedInput = """
@WireFormat
struct Foo {
    @WireFormatField(tag: 0) var name: String
}
"""

private let zeroTagRejectedExpanded = """
struct Foo {
    var name: String
}

extension Foo: WireFormatEncodable, WireFormatDecodable {
    public static var wireType: WireType {
        .lengthDelimited
    }

    public func encodePayload(into writer: inout WireFormatWriter) {
        writer.writeTag(tag: 0, wireType: String.wireType)
        name.encode(into: &writer)
    }

    public func encode(into writer: inout WireFormatWriter) {
        writer.writeLengthPrefixed { inner in
            encodePayload(into: &inner)
        }
    }

    public init(decodingPayload reader: inout WireFormatReader) throws {
        var _name: String? = nil
        while !reader.isAtEnd {
            let (tag, wt) = try reader.readTag()
            switch tag {
            case 0:
                _name = try String(from: &reader)
            default:
                try reader.skipUnknownField(wireType: wt)
            }
        }
        guard let _name else {
            throw WireFormatError.unknownTag(tag: 0, wireType: String.wireType)
        }
        self.name = _name
    }

    public init(from reader: inout WireFormatReader) throws {
        let len = Int(try reader.readVarint())
        let slice = try reader.readBytes(count: len)
        var inner = WireFormatReader(data: slice)
        try self.init(decodingPayload: &inner)
    }
}
"""

final class WireFormatFieldMacroRejectionTests: XCTestCase {
    // MARK: - Diagnostics

    func testReservedTagRejected() {
        assertMacroExpansion(
            reservedTagRejectedInput,
            expandedSource: reservedTagRejectedExpanded,
            diagnostics: [
                DiagnosticSpec(
                    message: "Tag 3 is reserved and cannot be used by field 'name'",
                    line: 3,
                    column: 5,
                    severity: .error,
                ),
            ],
            macros: fieldTestMacros,
        )
    }

    func testTagConflictRejected() {
        assertMacroExpansion(
            tagConflictRejectedInput,
            expandedSource: tagConflictRejectedExpanded,
            diagnostics: [
                DiagnosticSpec(
                    message: "Tag 5 is used by multiple fields",
                    line: 4,
                    column: 5,
                    severity: .error,
                ),
            ],
            macros: fieldTestMacros,
        )
    }

    func testZeroTagRejected() {
        assertMacroExpansion(
            zeroTagRejectedInput,
            expandedSource: zeroTagRejectedExpanded,
            diagnostics: [
                DiagnosticSpec(
                    message: "Field 'name' has explicit tag 0; tags must be > 0",
                    line: 3,
                    column: 5,
                    severity: .error,
                ),
            ],
            macros: fieldTestMacros,
        )
    }
}
