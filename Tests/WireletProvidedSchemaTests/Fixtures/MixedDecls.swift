// A plain protocol without @WireletProvided — must be ignored.
protocol PlainProtocol {
    func foo()
}

// @WireletProvided on a non-protocol — the parser only visits protocols,
// so this contributes nothing (the macro layer diagnoses it separately).
@WireletProvided
struct NotAProtocol {}

final class SomeClass {}
