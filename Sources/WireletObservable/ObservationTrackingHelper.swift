import Observation

/// Wraps `withObservationTracking` so the macro-generated JNI bridges and
/// tests share the same re-arm contract.
///
/// `withObservationTracking { … } onChange:` registers a one-shot
/// subscription: `onChange` runs exactly once on the next mutation of any
/// storage accessed inside the `read` closure. To keep emitting, the
/// caller must invoke `read(_:on:onChange:)` again from inside `onChange`.
/// The macro-generated Kotlin side does exactly that via the JNI bridge.
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
public enum ObservationTrackingHelper {
    /// Reads `keyPath` on `subject` under an Observation tracker. Returns
    /// the snapshot value and installs `onChange` as the one-shot callback.
    @inlinable
    public static func read<Subject: AnyObject, Value>(
        _ keyPath: KeyPath<Subject, Value>,
        on subject: Subject,
        onChange: @escaping @Sendable () -> Void
    ) -> Value {
        var snapshot: Value?
        withObservationTracking {
            snapshot = subject[keyPath: keyPath]
        } onChange: {
            onChange()
        }
        precondition(snapshot != nil, "withObservationTracking apply closure not called synchronously")
        return snapshot!
    }
}
