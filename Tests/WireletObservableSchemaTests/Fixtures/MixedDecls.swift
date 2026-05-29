/// Fixture for ObservableSchemaParserTests. Parsed as text — not compiled.
import Observation
import Wirelet
import WireletObservable

@WireFormat
public struct TodoItem: Equatable, Sendable {
    public var id: Int32
    public var title: String
    public var done: Bool
}

@Observable
public final class PlainObservable {
    public var count: Int32 = 0
}

public final class Plain {}
