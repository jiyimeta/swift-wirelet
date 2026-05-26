import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import WireletMacros

private let diagMacros: [String: Macro.Type] = [
    "WireFormat": WireFormatMacro.self,
    "WireFormatEnum": WireFormatEnumMacro.self,
    "WireFormatChoice": WireFormatChoiceMacro.self,
    "WireFormatField": WireFormatFieldMacro.self,
]

/// Diagnostic-coverage tests for the four macros. Each test exercises a
/// known misuse case and pins the exact diagnostic message + severity the
/// macro should emit. The matching expansion outputs are kept minimal —
/// the expansion-shape tests live in the per-macro `*ExpansionTests.swift`
/// files; here we only care that the diagnostic fires.
final class DiagnosticTests: XCTestCase {
    // MARK: - Case 1: @WireFormat on non-struct

    func testWireFormatOnClassIsRejected() {
        assertMacroExpansion(
            """
            @WireFormat
            class Foo {}
            """,
            expandedSource: """
            class Foo {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@WireFormat can only be applied to a struct",
                    line: 1,
                    column: 1,
                    severity: .error
                ),
            ],
            macros: diagMacros
        )
    }

    // MARK: - Case 2a: @WireFormatEnum on non-enum

    func testWireFormatEnumOnStructIsRejected() {
        assertMacroExpansion(
            """
            @WireFormatEnum
            struct Foo {}
            """,
            expandedSource: """
            struct Foo {}
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@WireFormatEnum can only be applied to an enum",
                    line: 1,
                    column: 1,
                    severity: .error
                ),
            ],
            macros: diagMacros
        )
    }

    // MARK: - Case 2b: @WireFormatEnum on enum without raw type

    func testWireFormatEnumWithoutRawTypeIsRejected() {
        assertMacroExpansion(
            """
            @WireFormatEnum
            enum Foo {
                case a
                case b
            }
            """,
            expandedSource: """
            enum Foo {
                case a
                case b
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@WireFormatEnum requires the enum to declare a raw type (e.g. ': UInt8' or ': String')",
                    line: 1,
                    column: 1,
                    severity: .error
                ),
            ],
            macros: diagMacros
        )
    }

    // MARK: - Case 3: @WireFormatChoice on enum without any associated values

    func testWireFormatChoiceWithoutAssociatedValuesWarns() {
        assertMacroExpansion(
            """
            @WireFormatChoice
            enum Color {
                case red
                case green
                case blue
            }
            """,
            expandedSource: """
            enum Color {
                case red
                case green
                case blue
            }

            extension Color: WireFormatEncodable, WireFormatDecodable {
                public static var wireType: WireType {
                    .lengthDelimited
                }

                public func encodePayload(into writer: inout WireFormatWriter) {
                    switch self {
                    case .red:
                        writer.writeVarint(UInt64(0))
                    case .green:
                        writer.writeVarint(UInt64(1))
                    case .blue:
                        writer.writeVarint(UInt64(2))
                    }
                }

                public func encode(into writer: inout WireFormatWriter) {
                    writer.writeLengthPrefixed { inner in
                        encodePayload(into: &inner)
                    }
                }

                public init(decodingPayload reader: inout WireFormatReader) throws {
                    let disc = try reader.readVarint()
                    switch disc {
                    case 0:
                        self = .red
                    case 1:
                        self = .green
                    case 2:
                        self = .blue
                    default:
                        throw WireFormatError.unknownChoiceDiscriminator(UInt32(truncatingIfNeeded: disc))
                    }
                }

                public init(from reader: inout WireFormatReader) throws {
                    let len = Int(try reader.readVarint())
                    let slice = try reader.readBytes(count: len)
                    var inner = WireFormatReader(data: slice)
                    try self.init(decodingPayload: &inner)
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@WireFormatChoice expects at least one case with associated values; prefer @WireFormatEnum for plain enums",
                    line: 1,
                    column: 1,
                    severity: .warning
                ),
            ],
            macros: diagMacros
        )
    }

    // MARK: - Case 5: @WireFormatField on computed property

    func testWireFormatFieldOnComputedPropertyWarns() {
        assertMacroExpansion(
            """
            @WireFormat
            struct Foo {
                var x: Int32
                @WireFormatField(tag: 2) var doubled: Int32 {
                    x * 2
                }
            }
            """,
            expandedSource: """
            struct Foo {
                var x: Int32
                var doubled: Int32 {
                    x * 2
                }
            }

            extension Foo: WireFormatEncodable, WireFormatDecodable {
                public static var wireType: WireType {
                    .lengthDelimited
                }

                public func encodePayload(into writer: inout WireFormatWriter) {
                    writer.writeTag(tag: 1, wireType: Int32.wireType)
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
                        case 1:
                            _x = try Int32(from: &reader)
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
            diagnostics: [
                DiagnosticSpec(
                    message: "@WireFormatField is ignored on computed property 'doubled'",
                    line: 4,
                    column: 5,
                    severity: .warning
                ),
            ],
            macros: diagMacros
        )
    }
}
