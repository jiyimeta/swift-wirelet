package io.github.jiyimeta.wirelet.example

import io.github.jiyimeta.wirelet.example.serialization.MessageCodec
import java.io.File

fun main(args: Array<String>) {
    require(args.size == 1) { "Usage: jvm-decoder <bytes-file>" }
    val bytes = File(args[0]).readBytes()
    val msg = MessageCodec.decode(bytes)
    println("id=${msg.id} text=${msg.text} tags=${msg.tags}")
    require(msg.id == 42) { "id mismatch: ${msg.id}" }
    require(msg.text == "hello") { "text mismatch: ${msg.text}" }
    require(msg.tags == listOf("a", "b")) { "tags mismatch: ${msg.tags}" }
    println("OK")
}
