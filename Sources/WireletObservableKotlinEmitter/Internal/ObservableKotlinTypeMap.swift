import WireletObservableSchema

/// Per-property render plan used by `ViewModelEmitter`. Carries the Kotlin
/// type for the StateFlow value, the Kotlin signature of the
/// `nativeXxxTrack(self, Runnable)` external function, the same for
/// `nativeXxxSet`, and the StateFlow read expression that goes inside
/// `readXxxWithTracking()`.
enum ObservableKotlinTypeMap {
    struct Plan {
        /// The Kotlin spelling of the StateFlow value type
        /// (e.g. `Int`, `String`, `List<TodoItem>`, `TodoItem?`).
        let kotlinType: String
        /// The Kotlin return type of `nativeXxxTrack` (`Int`, `String`,
        /// `ByteArray`, …). Always non-nullable for non-Optional shapes —
        /// the JNI side returns the encoded payload directly.
        let nativeTrackReturn: String
        /// The Kotlin parameter type of `nativeXxxSet` after `self: Long, …`.
        /// `nil` for read-only / non-supported properties.
        let nativeSetParam: String?
        /// Expression that turns the value returned by `nativeXxxTrack(...)`
        /// into the StateFlow value. `$1` is replaced with the call
        /// expression. E.g. for `[TodoItem]` →
        /// `WireletList.decode($1, TodoItemCodec)`.
        let decodeTemplate: String
        /// Expression that encodes the new StateFlow value before passing
        /// it to `nativeXxxSet`. `$1` is the Kotlin value. E.g.
        /// `TodoItemCodec.encode($1)`.
        let encodeTemplate: String?
        /// Imports the per-property render path adds. Joined with the
        /// view-model's overall import set and deduped at file render.
        let extraImports: Set<String>
    }

    static func plan(
        for property: ObservableProperty,
        config: ObservableCodegenConfig
    ) -> Plan {
        switch property.kind {
        case .primitive:
            return primitivePlan(swiftType: property.swiftTypeText)
        case .string:
            return Plan(
                kotlinType: "String",
                nativeTrackReturn: "String",
                nativeSetParam: "String",
                decodeTemplate: "$1",
                encodeTemplate: "$1",
                extraImports: []
            )
        case let .wireFormat(typeName):
            let codec = config.nameTransform.apply(to: typeName) + "Codec"
            return Plan(
                kotlinType: config.nameTransform.apply(to: typeName),
                nativeTrackReturn: "ByteArray",
                nativeSetParam: "ByteArray",
                decodeTemplate: "\(codec).decode($1)",
                encodeTemplate: "\(codec).encode($1)",
                extraImports: [
                    "\(config.modelPackage).\(config.nameTransform.apply(to: typeName))",
                    "\(config.codecPackage).\(codec)",
                ]
            )
        case let .wireFormatArray(elementTypeName):
            let codec = config.nameTransform.apply(to: elementTypeName) + "Codec"
            let kotlin = "List<\(config.nameTransform.apply(to: elementTypeName))>"
            return Plan(
                kotlinType: kotlin,
                nativeTrackReturn: "ByteArray",
                // Setter for array properties: re-encode every element with
                // a length-prefix + count header. Matches the WireletList
                // shape (Phase 3 runtime).
                nativeSetParam: "ByteArray",
                decodeTemplate: "WireletList.decode($1, \(codec))",
                encodeTemplate: "WireletList.encode($1, \(codec))",
                extraImports: [
                    "\(config.modelPackage).\(config.nameTransform.apply(to: elementTypeName))",
                    "\(config.codecPackage).\(codec)",
                    "\(config.runtimePackage).WireletList",
                ]
            )
        case .optionalPrimitive:
            // Optional primitives transport as a 0-or-1-byte ByteArray:
            // null = absent, single byte = present, raw value following.
            // Matches the macro setter signature (jbyteArray?). The runtime
            // exposes `WireletOptional` helpers that this plan references.
            let innerKotlin = kotlinPrimitive(swiftType: stripOptional(property.swiftTypeText))
            return Plan(
                kotlinType: "\(innerKotlin)?",
                nativeTrackReturn: "ByteArray?",
                nativeSetParam: "ByteArray?",
                decodeTemplate: "WireletOptional.decode\(innerKotlin)($1)",
                encodeTemplate: "WireletOptional.encode\(innerKotlin)($1)",
                extraImports: ["\(config.runtimePackage).WireletOptional"]
            )
        case .optionalString:
            return Plan(
                kotlinType: "String?",
                nativeTrackReturn: "String?",
                nativeSetParam: "String?",
                decodeTemplate: "$1",
                encodeTemplate: "$1",
                extraImports: []
            )
        case let .optionalWireFormat(typeName):
            let codec = config.nameTransform.apply(to: typeName) + "Codec"
            let kotlin = config.nameTransform.apply(to: typeName)
            return Plan(
                kotlinType: "\(kotlin)?",
                nativeTrackReturn: "ByteArray?",
                nativeSetParam: "ByteArray?",
                decodeTemplate: "$1?.let { \(codec).decode(it) }",
                encodeTemplate: "$1?.let { \(codec).encode(it) }",
                extraImports: [
                    "\(config.modelPackage).\(kotlin)",
                    "\(config.codecPackage).\(codec)",
                ]
            )
        }
    }

    /// Returns the JNI-symmetric Kotlin type + native shape for a Swift
    /// primitive type text. Mirrors the macro's marshaling rules table
    /// (spec line 211–224): `Int32` → `Int`, `Int64` → `Long`, `Bool` →
    /// `Boolean`, etc.
    static func primitivePlan(swiftType: String) -> Plan {
        let kotlin = kotlinPrimitive(swiftType: swiftType)
        return Plan(
            kotlinType: kotlin,
            nativeTrackReturn: kotlin,
            nativeSetParam: kotlin,
            decodeTemplate: "$1",
            encodeTemplate: "$1",
            extraImports: []
        )
    }

    static func kotlinPrimitive(swiftType: String) -> String {
        switch swiftType {
        case "Int8", "Int16", "Int32", "UInt8", "UInt16": return "Int"
        case "Int64", "UInt32", "UInt64": return "Long"
        case "Bool": return "Boolean"
        case "Float": return "Float"
        case "Double": return "Double"
        default: return swiftType
        }
    }

    private static func stripOptional(_ typeText: String) -> String {
        if typeText.hasSuffix("?") {
            return String(typeText.dropLast())
        }
        if typeText.hasPrefix("Optional<"), typeText.hasSuffix(">") {
            return String(typeText.dropFirst("Optional<".count).dropLast())
        }
        return typeText
    }
}
