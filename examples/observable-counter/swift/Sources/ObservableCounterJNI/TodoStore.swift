import Wirelet

#if os(Android)
import Foundation
import WireletObservable

/// Hand-written stand-in for the Phase 2 generated proxy. Mirrors the
/// future `@WireletProvided protocol TodoStore` whose implementation is
/// supplied on the Kotlin side.
protocol TodoStore {
    func loadAll() -> [TodoItem]
    func add(_ item: TodoItem)
    func remove(_ id: Int32)
}

/// Forwards each `TodoStore` call to a Kotlin `TodoStoreNativeAdapter`
/// over JNI. Wire-method names + descriptors must match the Kotlin
/// adapter (addWire ([B)V, removeWire (I)V, loadAllWire ()[B).
struct TodoStoreProxy: TodoStore {
    let adapter: JObject

    func loadAll() -> [TodoItem] {
        guard let bytes = adapter.callBytes(method: "loadAllWire", signature: "()[B") else {
            return []
        }
        var reader = WireFormatReader(data: Data(bytes))
        guard let count = try? reader.readVarint() else { return [] }
        var items: [TodoItem] = []
        items.reserveCapacity(Int(count))
        for _ in 0..<Int(count) {
            guard let item = try? TodoItem(from: &reader) else { return items }
            items.append(item)
        }
        return items
    }

    func add(_ item: TodoItem) {
        let bytes = [UInt8](item.encodeToData())
        adapter.callVoid(method: "addWire", signature: "([B)V", [.bytes(bytes)])
    }

    func remove(_ id: Int32) {
        adapter.callVoid(method: "removeWire", signature: "(I)V", [.int(id)])
    }
}
#endif
