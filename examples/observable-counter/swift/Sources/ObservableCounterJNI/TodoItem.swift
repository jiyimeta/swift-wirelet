import Wirelet

/// Single to-do row. Bridged across the JNI boundary as a `WireFormat` TLV
/// payload; the macro-emitted `TodoItemCodec` on the Kotlin side decodes
/// the same bytes back into a data class. Fields ordered to match the
/// schema in `docs/superpowers/specs/2026-05-29-wirelet-observable-bridge-design.md`.
@WireFormat
public struct TodoItem: Equatable, Sendable {
    public var id: Int32
    public var title: String
    public var done: Bool

    public init(id: Int32, title: String, done: Bool) {
        self.id = id
        self.title = title
        self.done = done
    }
}
