/// Fixture: exercises explicit `@WireFormatField(tag:)`, `reservedTags:`
/// on `@WireFormat`, and Optional field detection (sugared `T?` form).
@WireFormat(reservedTags: [2, 4])
struct TaggedRecord {
    var a: Int32                                // implicit 1
    @WireFormatField(tag: 7) var b: Int32       // explicit 7
    var c: Int32?                               // implicit (skips 2 / 4): 3
    var d: Int32                                // implicit: 5
}
