# Schema evolution

What you can change in a `@WireFormat` type without breaking peers that
were built against an earlier version, and what you cannot. "Forward
compatibility" means a new producer can talk to an old consumer;
"backward compatibility" means an old producer can talk to a new
consumer. Both directions matter when the Swift and Kotlin sides of a
deployment ship on different cadences.

## Quick reference

| Change                                          | Forward-compat (new wire → old reader) | Backward-compat (old wire → new reader) |
|-------------------------------------------------|----------------------------------------|------------------------------------------|
| Append `Optional<T>` field                      | safe                                   | safe                                     |
| Append non-`Optional` field                     | safe (old reader ignores)              | UNSAFE (new reader misses required field)|
| Remove field                                    | safe if marked `reserved`              | safe                                     |
| Rename field                                    | safe (tags identify, not names)        | safe                                     |
| Renumber tag                                    | breaking                               | breaking                                 |
| Change wire type (e.g. `Int` → `String`)        | breaking                               | breaking                                 |
| `Optional<T>` → `T`                             | breaking                               | breaking                                 |
| `T` → `Optional<T>`                             | safe                                   | safe                                     |
| Add `@WireFormatChoice` case                    | configurable on read (default: throw)  | safe                                     |
| Add `@WireFormatEnum` case                      | old reader throws `.invalidCount`      | safe                                     |

## Narrative

### Append `Optional<T>` field

Appending a new field with an `Optional<T>` type is the universally
safe extension. Old readers see an unknown tag and skip it in O(1)
using the wire-type code. New readers see the absence of the tag and
leave the optional as `nil`.

```swift
// v0.1
@WireFormat struct Profile { var name: String }

// v0.2 — backwards- and forwards-compatible
@WireFormat struct Profile {
    var name: String
    var nickname: String?   // new
}
```

### Append non-`Optional` field

Appending a required field is forward-compatible (old readers skip the
unknown tag) but backward-incompatible: a new reader decoding an old
payload will not find the field, the macro-generated decoder will fall
out of the loop with the property still set to its default temporary
`nil`, and the post-loop `guard let` will throw a missing-field error.

Strongly prefer marking new fields optional. Promote to required only
in a follow-up migration once every producer has been upgraded.

### Remove field

Removing a field is backward-compatible (the new reader simply has no
slot for the old tag, and the macro-generated `switch` falls into the
unknown-tag branch which skips by wire type). It is forward-compatible
**only** if the removed tag is recorded in the struct's reserved set,
because the implicit-tag counter would otherwise reuse it for a future
field. Reusing a tag for a different field swaps the meanings of old
and new payloads — a silent corruption.

```swift
// v0.1
@WireFormat struct Profile { var name: String; var legacyHandle: String }

// v0.2 — drop legacyHandle, mark its tag reserved
@WireFormat(reservedTags: [2])
struct Profile {
    var name: String
    // (tag 2 retired)
}
```

### Rename field

Tag numbers — not Swift identifiers — identify fields on the wire.
Renaming `nickname` to `displayName` is a Swift-side refactor that has
no on-wire effect. Both directions remain compatible. (The Kotlin
emitter regenerates the codec with the new name; producers and
consumers that ship a mix of old and new names still interoperate
because the bytes only carry tags.)

### Renumber tag

Changing the explicit `@WireFormatField(tag:)` of a field — or
reordering stored properties in a way that shifts implicit tags —
breaks both directions. Old wire bytes will surface under the wrong
field on the new reader; new wire bytes will surface under the wrong
field on the old reader. Treat tag assignments as committed once a
type has been published.

### Change wire type

A change like `Int32` → `String` or `Float` → `Double` flips the
3-bit wire-type code in the field's tag varint. Old readers will see
a `WireFormatError.unknownTag` (with the new wire type) and either
skip or throw depending on their strictness setting; new readers
decoding old payloads will mis-parse, because the new decoder reads
the payload according to the new type's rules. Breaking in both
directions; rename the field and add a new one instead.

### `Optional<T>` → `T`

Tightening optional to required is breaking. Old wire bytes can omit
the field; the new reader's post-loop required-field guard then throws.
Avoid this — the wire-stable migration is to keep the field optional
forever, even if every producer in your codebase has started filling
it.

### `T` → `Optional<T>`

Relaxing required to optional is safe both directions: old producers
always emit the field (so new readers see it set), old readers still
expect the field and find it.

### Add `@WireFormatChoice` case

Appending a case to a choice is backward-compatible (the new reader
trivially handles the new discriminator). It is forward-compatible only
when the old reader is configured to tolerate unknown discriminators —
the default behaviour today is to throw
`WireFormatError.unknownChoiceDiscriminator`. Plan for this by either
keeping a relaxed-mode flag on the read path or by avoiding new cases
during cross-version overlap windows.

```swift
@WireFormatChoice
enum Payload {
    case text(String)
    case image(Data)
    case video(Data)   // appended in v0.2
}
```

A v0.1 reader handed a `.video` discriminator throws by default.

### Add `@WireFormatEnum` case

Appending a case to an enum (with the default integer raw) is
backward-compatible. Old readers given the new rawValue look up the
matching case via `init(rawValue:)`, fail, and throw
`WireFormatError.invalidCount(raw)`. Reordering or removing cases
re-assigns rawValues to different cases and is breaking in both
directions — never reorder once a type has been published.

## Operational guidance

- **Maintain a reserved-tag log**: every time a field is deleted, add
  its tag to `@WireFormat(reservedTags: [...])` and leave a comment
  pointing at the change.
- **Pin Swift and Kotlin to the same wirelet version during rollout**:
  the wire spec is versioned (currently v0.1) and a breaking change to
  the spec itself — e.g. new wire-type code, change to ZigZag, change to
  canonical dictionary ordering — is not field-level evolution and is
  not covered by this guide. Such changes bump the spec version and
  require both sides to upgrade in lockstep.
- **Refresh conformance fixtures on every wire change**: the
  `kotlin/conformance-tests/fixtures/*.bin` bytes assert byte-for-byte
  parity. A wire-affecting PR that does not regenerate them will fail
  CI; a wire-affecting PR that regenerates them without updating the
  spec doc here loses the audit trail.
