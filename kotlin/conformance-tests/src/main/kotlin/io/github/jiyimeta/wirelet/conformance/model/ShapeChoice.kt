// Hand-authored sealed-class hierarchy mirroring
// @WireFormatChoice enum ShapeChoice. The codec emitter expects:
//   - top-level sealed type `ShapeChoice` with nested `Point` / `Label`
//     case classes
//   - each case's positional payload becomes `argN` constructor params
package io.github.jiyimeta.wirelet.conformance.model

public sealed class ShapeChoice {
    public data class Point(val arg0: Int, val arg1: Int) : ShapeChoice()
    public data class Label(val arg0: String) : ShapeChoice()
}
