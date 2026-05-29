/// Fixture for ObservableSchemaParserTests. Parsed as text — not compiled.
import Observation
import WireletObservable

@WireletObservable
@Observable
public final class CounterVM {
    public var count: Int32 = 0

    public init() {}

    @WireletExpose
    public func increment() {
        count += 1
    }
}
