// Hand-authored data class — the emitter generates the codec but not the
// model type (Task 2.13 limitation). Field types must match the Kotlin
// type mapping used by the codec exactly.
package io.github.jiyimeta.wirelet.conformance.model

public data class Primitives(
    val u32: UInt,
    val i32: Int,
    val f: Float,
    val d: Double,
    val s: String,
    val b: Boolean,
)
