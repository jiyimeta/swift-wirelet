// Hand-authored data class — the emitter generates the codec but not the
// model type. Mirrors Tests/ConformanceTests/FixtureSchemas.swift's
// `MapHolder { var m: [String: Int32] }`.
package io.github.jiyimeta.wirelet.conformance.model

public data class MapHolder(
    val m: Map<String, Int>,
)
