#if os(Android)
import CWireletJNI
import Foundation
import Wirelet

/// Helpers used by macro-generated `@_cdecl` JNI bridges. Keeping the
/// pointer ceremony out of the macro expansion makes diffs of generated
/// code readable and lets us unit-test the marshaling separately.
public enum WireletObservableJNI {

    /// Allocates a `jlong` that owns a +1 retain on `value`. The Kotlin
    /// side stores this in a `Long` and passes it back as `self` to every
    /// bridge call. Released via `release(_:)`.
    public static func retain<T: AnyObject>(_ value: T) -> jlong {
        let unmanaged = Unmanaged.passRetained(value)
        return jlong(Int(bitPattern: unmanaged.toOpaque()))
    }

    /// Borrows a reference from a `jlong` without changing retain count.
    /// Safe for the duration of the JNI call; do not store the returned
    /// reference beyond it.
    public static func unwrap<T: AnyObject>(_ pointer: jlong, as: T.Type = T.self) -> T {
        let opaque = UnsafeRawPointer(bitPattern: Int(pointer))!
        return Unmanaged<T>.fromOpaque(opaque).takeUnretainedValue()
    }

    /// Drops the +1 retain previously taken by `retain(_:)`. Called from
    /// the Kotlin side's `ViewModel.onCleared()`. Subsequent calls with
    /// the same `pointer` are undefined behavior; the Kotlin side must
    /// null its `nativePtr` after `release`.
    public static func release<T: AnyObject>(_ pointer: jlong, as: T.Type = T.self) {
        let opaque = UnsafeRawPointer(bitPattern: Int(pointer))!
        Unmanaged<T>.fromOpaque(opaque).release()
    }

    /// Encodes a `@WireFormat` value to a freshly-allocated `jbyteArray`.
    public static func encode<T: WireFormatEncodable>(
        _ value: T,
        env: UnsafeMutablePointer<JNIEnv?>
    ) -> jbyteArray? {
        var writer = WireFormatWriter()
        value.encode(into: &writer)
        return jbyteArray(env: env, bytes: writer.data)
    }

    /// Encodes an array of `@WireFormat` values as `[count varint][payload…]`.
    public static func encodeArray<T: WireFormatEncodable>(
        _ array: [T],
        env: UnsafeMutablePointer<JNIEnv?>
    ) -> jbyteArray? {
        var writer = WireFormatWriter()
        writer.writeVarint(UInt64(array.count))
        for element in array {
            element.encode(into: &writer)
        }
        return jbyteArray(env: env, bytes: writer.data)
    }

    /// Decodes a Kotlin-side `jbyteArray` payload into a Swift `Data`.
    public static func dataFromByteArray(
        _ bytes: jbyteArray?,
        env: UnsafeMutablePointer<JNIEnv?>
    ) -> Data {
        guard let bytes, let envValue = env.pointee else { return Data() }
        let length = Int(envValue.pointee.GetArrayLength(env, bytes))
        var buffer = [UInt8](repeating: 0, count: length)
        buffer.withUnsafeMutableBufferPointer { raw in
            raw.withMemoryRebound(to: jbyte.self) { jbytes in
                envValue.pointee.GetByteArrayRegion(env, bytes, 0, jsize(length), jbytes.baseAddress)
            }
        }
        return Data(buffer)
    }
}

/// Small wrapper so call sites read top-down.
private func jbyteArray(
    env: UnsafeMutablePointer<JNIEnv?>,
    bytes: Data
) -> jbyteArray? {
    guard let envValue = env.pointee else { return nil }
    guard let array = envValue.pointee.NewByteArray(env, jsize(bytes.count)) else {
        return nil
    }
    bytes.withUnsafeBytes { raw in
        guard let base = raw.bindMemory(to: jbyte.self).baseAddress else { return }
        envValue.pointee.SetByteArrayRegion(env, array, 0, jsize(bytes.count), base)
    }
    return array
}
#endif
