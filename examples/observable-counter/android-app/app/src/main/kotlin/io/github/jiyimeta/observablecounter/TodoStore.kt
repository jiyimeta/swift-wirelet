package io.github.jiyimeta.observablecounter

import io.github.jiyimeta.wirelet.observable.WireletList

/**
 * Hand-written stand-in for the Phase 3 generated `@WireletProvided`
 * artifacts. `TodoStore` is the friendly interface an app implements;
 * `TodoStoreNativeAdapter` exposes byte-level wire methods the Swift
 * proxy invokes over JNI; `InMemoryTodoStore` is a trivial impl; and
 * `StoreProbe` holds the `external fun` the instrumented test drives.
 */
interface TodoStore {
    fun loadAll(): List<TodoItem>
    fun add(item: TodoItem)
    fun remove(id: Int)
}

/** Trivial impl so the round trip has something to mutate. */
class InMemoryTodoStore : TodoStore {
    val items = mutableListOf<TodoItem>()
    override fun loadAll(): List<TodoItem> = items.toList()
    override fun add(item: TodoItem) { items.add(item) }
    override fun remove(id: Int) { items.removeAll { it.id == id } }
}

/**
 * Byte-level shim the Swift `TodoStoreProxy` targets via `GetMethodID`.
 * Method names + JNI descriptors here are the contract the Swift side
 * must match exactly:
 *   addWire     ([B)V
 *   removeWire  (I)V
 *   loadAllWire ()[B
 *
 * The byte layouts mirror the known-correct `items` StateFlow path
 * (`TodoListVMViewModel`): a single item is `TodoItemCodec.encode`
 * (top-level length-prefixed) and a list is `WireletList.encode` with
 * the `TodoItemCodec::encodePayload` element encoder.
 */
class TodoStoreNativeAdapter(private val impl: TodoStore) {
    fun addWire(bytes: ByteArray) {
        impl.add(TodoItemCodec.decode(bytes))
    }

    fun removeWire(id: Int) {
        impl.remove(id)
    }

    fun loadAllWire(): ByteArray =
        WireletList.encode(impl.loadAll(), TodoItemCodec::encodePayload)
}

/**
 * JNI entry the test drives. The native function is resolved by the
 * default JNI name `Java_io_github_jiyimeta_observablecounter_StoreProbe_nativeRoundTrip`
 * exported (as `@_cdecl`) from libObservableCounterJNI.so.
 */
object StoreProbe {
    init { System.loadLibrary("ObservableCounterJNI") }

    /**
     * Hands `adapter` to Swift. Swift adds two items and removes one via
     * the adapter, then returns `loadAll().count` so the test can assert
     * the full Swift -> Kotlin round trip (arg marshaling + byte return
     * decode) without re-decoding bytes in Kotlin.
     */
    external fun nativeRoundTrip(adapter: TodoStoreNativeAdapter): Int
}
