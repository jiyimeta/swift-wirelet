import Testing
import Wirelet
import WireletProvided

// A @WireFormat value used by the provided protocol below.
@WireFormat
struct Note: Equatable, Sendable {
    var id: Int32
    var text: String
}

// On Apple platforms @WireletProvided is an inert marker: this is a plain
// Swift protocol, so a host fake can conform directly.
@WireletProvided
protocol NoteStore {
    func loadAll() -> [Note]
    func add(_ note: Note)
    func remove(_ id: Int32)
}

// A plain Swift fake conformance — only possible because the marker emits
// no proxy/requirements on the host.
final class FakeNoteStore: NoteStore {
    private(set) var notes: [Note] = []
    func loadAll() -> [Note] { notes }
    func add(_ note: Note) { notes.append(note) }
    func remove(_ id: Int32) { notes.removeAll { $0.id == id } }
}

// A consumer that takes the provided protocol by injection — mirrors how a
// @WireletObservable class would on the host (where @WireletProvided is inert).
final class NoteListModel {
    private let store: NoteStore
    private(set) var notes: [Note]
    init(store: NoteStore) {
        self.store = store
        self.notes = store.loadAll()
    }
    func add(_ note: Note) {
        store.add(note)
        notes = store.loadAll()
    }
}

@Suite("WireletProvided Apple-build inertness")
struct InertnessTests {
    @Test func fakeConformanceUsableOnHost() {
        let fake = FakeNoteStore()
        let model = NoteListModel(store: fake)
        #expect(model.notes.isEmpty)

        model.add(Note(id: 1, text: "first"))
        model.add(Note(id: 2, text: "second"))
        #expect(model.notes.count == 2)
        #expect(fake.notes.map(\.id) == [1, 2])
        #expect(model.notes.last?.text == "second")
    }

    @Test func injectedModelHydratesFromStore() {
        let fake = FakeNoteStore()
        fake.add(Note(id: 7, text: "seed"))
        let model = NoteListModel(store: fake)
        #expect(model.notes == [Note(id: 7, text: "seed")])
    }
}
