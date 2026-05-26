import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest
@testable import WireletMacros

private let testMacros: [String: Macro.Type] = [
    "WireFormatEnum": WireFormatEnumMacro.self,
]

final class WireFormatEnumMacroExpansionTests: XCTestCase {
    func testIntegerRawEnumExpansion() {
        assertMacroExpansion(
            """
            @WireFormatEnum
            enum Color: UInt8, CaseIterable, Equatable {
                case red, green, blue
            }
            """,
            expandedSource: """
            enum Color: UInt8, CaseIterable, Equatable {
                case red, green, blue
            }

            extension Color: WireFormatEncodable, WireFormatDecodable {
                public static var wireType: WireType {
                    UInt8.wireType
                }

                public func encodePayload(into writer: inout WireFormatWriter) {
                    rawValue.encodePayload(into: &writer)
                }

                public init(decodingPayload reader: inout WireFormatReader) throws {
                    let raw = try UInt8(decodingPayload: &reader)
                    guard let v = Color(rawValue: raw) else {
                        throw WireFormatError.invalidCount(Int32(truncatingIfNeeded: raw))
                    }
                    self = v
                }

                public func encode(into writer: inout WireFormatWriter) {
                    encodePayload(into: &writer)
                }

                public init(from reader: inout WireFormatReader) throws {
                    try self.init(decodingPayload: &reader)
                }
            }
            """,
            macros: testMacros
        )
    }

    func testStringRawEnumExpansion() {
        assertMacroExpansion(
            """
            @WireFormatEnum
            enum Tone: String, CaseIterable, Equatable {
                case major, minor
            }
            """,
            expandedSource: """
            enum Tone: String, CaseIterable, Equatable {
                case major, minor
            }

            extension Tone: WireFormatEncodable, WireFormatDecodable {
                public static var wireType: WireType {
                    String.wireType
                }

                public func encodePayload(into writer: inout WireFormatWriter) {
                    rawValue.encodePayload(into: &writer)
                }

                public init(decodingPayload reader: inout WireFormatReader) throws {
                    let raw = try String(decodingPayload: &reader)
                    guard let v = Tone(rawValue: raw) else {
                        throw WireFormatError.invalidCount(Int32(truncatingIfNeeded: raw.hashValue))
                    }
                    self = v
                }

                public func encode(into writer: inout WireFormatWriter) {
                    encodePayload(into: &writer)
                }

                public init(from reader: inout WireFormatReader) throws {
                    try self.init(decodingPayload: &reader)
                }
            }
            """,
            macros: testMacros
        )
    }
}
