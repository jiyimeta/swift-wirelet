// Hand-authored data class (the emitter generates the codec but not the model type).
package io.github.jiyimeta.wirelet.example.model

public data class Message(
    val id: Int,
    val text: String,
    val tags: List<String>,
)
