import Wirelet

#if os(Android)
import CWireletJNI
import Foundation
import WireletObservable

/// Test-only JNI entry. Receives the Kotlin `TodoStoreNativeAdapter`,
/// drives a Swift -> Kotlin round trip through `TodoStoreProxy`, and
/// returns the resulting `loadAll().count` so the instrumented test can
/// assert the full path (jbyteArray arg + jint arg + jbyteArray return).
@_cdecl("Java_io_github_jiyimeta_observablecounter_StoreProbe_nativeRoundTrip")
public func storeProbeNativeRoundTrip(
    _ env: UnsafeMutablePointer<JNIEnv?>?,
    _ clazz: jobject?,
    _ adapter: jobject?
) -> jint {
    guard let env, let object = JObject(env: env, jobject: adapter) else { return -1 }
    let store: TodoStore = TodoStoreProxy(adapter: object)
    store.add(TodoItem(id: 1, title: "from-swift-1", done: false))
    store.add(TodoItem(id: 2, title: "from-swift-2", done: true))
    store.remove(1)
    return jint(store.loadAll().count)
}
#endif
