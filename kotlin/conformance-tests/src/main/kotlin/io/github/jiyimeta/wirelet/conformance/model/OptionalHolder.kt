// Hand-authored data class — the emitter generates the codec but not the
// model type (Task 2.13 limitation).
package io.github.jiyimeta.wirelet.conformance.model

public data class OptionalHolder(
    val a: Int,
    val b: Int?,
)

public data class OptionalHolderV2(
    val a: Int,
    val b: Int?,
    val c: String?,
)
