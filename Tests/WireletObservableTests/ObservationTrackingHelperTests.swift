import Observation
import Testing
@testable import WireletObservable

@Observable
final class Counter {
    var value: Int = 0
}

@Suite struct ObservationTrackingHelperTests {
    @Test func readReturnsCurrentValue() {
        let counter = Counter()
        counter.value = 7
        let snapshot = ObservationTrackingHelper.read(\Counter.value, on: counter) {
            // onChange ignored for this assertion
        }
        #expect(snapshot == 7)
    }

    @Test func onChangeFiresOnceForMutation() {
        let counter = Counter()
        // nonisolated(unsafe): onChange fires synchronously on the mutating
        // thread (documented Observation behaviour), so no concurrent access.
        nonisolated(unsafe) var fired = 0
        _ = ObservationTrackingHelper.read(\Counter.value, on: counter) {
            fired += 1
        }
        counter.value = 1
        // withObservationTracking dispatches onChange synchronously on the
        // mutating thread; no async wait needed in this test.
        #expect(fired == 1)
    }

    @Test func onChangeFiresOnlyOnceWithoutReArm() {
        let counter = Counter()
        // nonisolated(unsafe): onChange fires synchronously on the mutating
        // thread (documented Observation behaviour), so no concurrent access.
        nonisolated(unsafe) var fired = 0
        _ = ObservationTrackingHelper.read(\Counter.value, on: counter) {
            fired += 1
        }
        #expect(fired == 0, "callback must not run until a mutation occurs")
        counter.value = 1
        #expect(fired == 1, "first mutation triggers exactly one fire")
        counter.value = 2
        #expect(fired == 1, "second mutation must not re-fire — subscription is one-shot")
    }
}
