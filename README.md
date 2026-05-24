# wirelet

A Swift-macro-driven wire-format toolkit for cross-runtime IPC between Swift and Kotlin.

> **Not Square Wire.** Square Wire is a protobuf-derived schema/codec generator for the JVM; wirelet is a SwiftSyntax-driven generator producing Swift codecs (via Swift macros) and Kotlin codecs (via a CLI emitter) from a single `@WireFormat` Swift source-of-truth declaration. Different problem, different mechanism.

Status: **pre-alpha**, private repo. v0.1 ships Swift + Kotlin emitters; further languages and Maven Central publishing are deferred.
