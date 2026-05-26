import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import WireletMacros

private let testMacros: [String: Macro.Type] = [
    "WireFormat": WireFormatMacro.self,
]

final class WireFormatMacroExpansionTests: XCTestCase {
    func testEmptyStructExpansion() {
        assertMacroExpansion(
            """
            @WireFormat
            struct Empty {}
            """,
            expandedSource: """
            struct Empty {}

            extension Empty: WireFormatEncodable, WireFormatDecodable {
                public static var wireType: WireType {
                    .lengthDelimited
                }

                public func encodePayload(into writer: inout WireFormatWriter) {

                }

                public func encode(into writer: inout WireFormatWriter) {
                    writer.writeLengthPrefixed { inner in
                        encodePayload(into: &inner)
                    }
                }

                public init(decodingPayload reader: inout WireFormatReader) throws {

                }

                public init(from reader: inout WireFormatReader) throws {
                    let len = Int(try reader.readVarint())
                    let slice = try reader.readBytes(count: len)
                    var inner = WireFormatReader(data: slice)
                    try self.init(decodingPayload: &inner)
                }
            }
            """,
            macros: testMacros
        )
    }

    func testSingleFieldTaggedExpansion() {
        assertMacroExpansion(
            """
            @WireFormat
            struct Point {
                var x: Int32
            }
            """,
            expandedSource: """
            struct Point {
                var x: Int32
            }

            extension Point: WireFormatEncodable, WireFormatDecodable {
                public static var wireType: WireType {
                    .lengthDelimited
                }

                public func encodePayload(into writer: inout WireFormatWriter) {
                    writer.writeTag(tag: 1, wireType: Int32.wireType)
                    x.encodePayload(into: &writer)
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
                        case 1:
                            _x = try Int32(decodingPayload: &reader)
                        default:
                            try reader.skipUnknownField(wireType: wt)
                        }
                    }
                    guard let _x else {
                        throw WireFormatError.unknownTag(tag: 1, wireType: Int32.wireType)
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
            """,
            macros: testMacros
        )
    }

    func testTwoFieldImplicitTags() {
        assertMacroExpansion(
            """
            @WireFormat
            struct Point {
                var x: Int32
                var y: Int32
            }
            """,
            expandedSource: """
            struct Point {
                var x: Int32
                var y: Int32
            }

            extension Point: WireFormatEncodable, WireFormatDecodable {
                public static var wireType: WireType {
                    .lengthDelimited
                }

                public func encodePayload(into writer: inout WireFormatWriter) {
                    writer.writeTag(tag: 1, wireType: Int32.wireType)
                    x.encodePayload(into: &writer)
                    writer.writeTag(tag: 2, wireType: Int32.wireType)
                    y.encodePayload(into: &writer)
                }

                public func encode(into writer: inout WireFormatWriter) {
                    writer.writeLengthPrefixed { inner in
                        encodePayload(into: &inner)
                    }
                }

                public init(decodingPayload reader: inout WireFormatReader) throws {
                    var _x: Int32? = nil
                    var _y: Int32? = nil
                    while !reader.isAtEnd {
                        let (tag, wt) = try reader.readTag()
                        switch tag {
                        case 1:
                            _x = try Int32(decodingPayload: &reader)
                        case 2:
                            _y = try Int32(decodingPayload: &reader)
                        default:
                            try reader.skipUnknownField(wireType: wt)
                        }
                    }
                    guard let _x else {
                        throw WireFormatError.unknownTag(tag: 1, wireType: Int32.wireType)
                    }
                    self.x = _x
                    guard let _y else {
                        throw WireFormatError.unknownTag(tag: 2, wireType: Int32.wireType)
                    }
                    self.y = _y
                }

                public init(from reader: inout WireFormatReader) throws {
                    let len = Int(try reader.readVarint())
                    let slice = try reader.readBytes(count: len)
                    var inner = WireFormatReader(data: slice)
                    try self.init(decodingPayload: &inner)
                }
            }
            """,
            macros: testMacros
        )
    }
}
