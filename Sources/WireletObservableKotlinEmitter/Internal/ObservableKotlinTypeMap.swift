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
        /// `WireletList.decode($1, TodoItemCodec::decodePayload)`.
        let decodeTemplate: String
        /// Expression that encodes the new StateFlow value before passing
        /// it to `nativeXxxSet`. `$1` is the Kotlin value. E.g. for
        /// `[TodoItem]` → `WireletList.encode($1, TodoItemCodec::encodePayload)`.
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
                decodeTemplate: "WireletList.decode($1, \(codec)::decodePayload)",
                encodeTemplate: "WireletList.encode($1, \(codec)::encodePayload)",
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

    // MARK: - Invoke arg mapping (method parameters)

    /// Maps a Swift method-parameter type to its Kotlin representation for
    /// `@WireletExpose` method emission. Returns the public Kotlin type, the
    /// `external fun` parameter type, and an encode expression factory.
    static func invokeArg(
        forArgType swiftType: String,
        config: ObservableCodegenConfig
    ) -> (kotlinType: String, externalFunType: String, encodeExpr: (String) -> String) {
        switch InvokeArgClassifier.classify(swiftType) {
        case .primitive(_, let cast):
            let kt = kotlinPrimitive(swiftType: cast)
            return (kt, kt, { name in name })
        case .bool:
            return ("Boolean", "Boolean", { name in name })
        case .string:
            return ("String", "String", { name in name })
        case .wireFormat(let typeName):
            let kt = config.nameTransform.apply(to: typeName)
            let codec = kt + "Codec"
            return (kt, "ByteArray", { name in "\(codec).encode(\(name))" })
        case .optionalPrimitive(let inner):
            let kt = kotlinPrimitive(swiftType: inner)
            return ("\(kt)?", "ByteArray?",
                    { name in "WireletOptional.encode\(kt)(\(name))" })
        case .optionalString:
            return ("String?", "String?", { name in name })
        case .optionalWireFormat(let typeName):
            let kt = config.nameTransform.apply(to: typeName)
            let codec = kt + "Codec"
            return ("\(kt)?", "ByteArray?",
                    { name in "\(name)?.let { \(codec).encode(it) }" })
        case .array(let elementTypeName):
            // Array of the primitive `String`: there is no generated
            // `StringCodec`, so route through the runtime's `encodeStrings`
            // (bare-UTF-8 element payloads, length-prefixed by WireletList).
            if case .string = InvokeArgClassifier.classify(elementTypeName) {
                return ("List<String>", "ByteArray",
                        { name in "WireletList.encodeStrings(\(name))" })
            }
            let kt = config.nameTransform.apply(to: elementTypeName)
            let codec = kt + "Codec"
            let listType = "List<\(kt)>"
            return (listType, "ByteArray",
                    { name in "WireletList.encode(\(name), \(codec)::encodePayload)" })
        }
    }

    // MARK: - Invoke return mapping

    /// Maps a Swift `@WireletExpose` return type to its Kotlin representation:
    /// the public return type, the `external fun` return type (the raw JNI
    /// shape), a decode-expression factory (`$0` is the native call
    /// expression), and the imports the decode needs. Mirrors `invokeArg`,
    /// reusing the same decode templates the observable StateFlows use. The
    /// caller handles a `Void` return (no return clause) before calling this.
    static func invokeReturn(
        forReturnType swiftType: String,
        config: ObservableCodegenConfig
    ) -> (kotlinType: String, externalFunType: String, decodeExpr: (String) -> String, imports: Set<String>) {
        switch InvokeArgClassifier.classify(swiftType) {
        case .primitive(_, let cast):
            let kt = kotlinPrimitive(swiftType: cast)
            return (kt, kt, { $0 }, [])
        case .bool:
            return ("Boolean", "Boolean", { $0 }, [])
        case .string:
            return ("String", "String", { $0 }, [])
        case .wireFormat(let typeName):
            let kt = config.nameTransform.apply(to: typeName)
            let codec = kt + "Codec"
            return (kt, "ByteArray", { "\(codec).decode(\($0))" },
                    ["\(config.modelPackage).\(kt)", "\(config.codecPackage).\(codec)"])
        case .array(let elementTypeName):
            let kt = config.nameTransform.apply(to: elementTypeName)
            let codec = kt + "Codec"
            return ("List<\(kt)>", "ByteArray", { "WireletList.decode(\($0), \(codec)::decodePayload)" },
                    [
                        "\(config.modelPackage).\(kt)",
                        "\(config.codecPackage).\(codec)",
                        "\(config.runtimePackage).WireletList",
                    ])
        case .optionalString, .optionalPrimitive, .optionalWireFormat:
            // Optional returns are unsupported (the Swift bridge emits a build-time #error first). Provide a
            // harmless mapping so emission itself doesn't crash; the build fails on the Swift side.
            return ("Unit", "Unit", { $0 }, [])
        }
    }
}
