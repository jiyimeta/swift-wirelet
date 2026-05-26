# wirelet wire format — language-neutral binary specification, v0.1

This document defines the on-the-wire byte layout produced by wirelet's
Swift macros and consumed (or produced) by the Kotlin emitter. Any
conforming implementation in any language must read and write identical
bytes given the same logical value.

The format is loosely modelled on Protocol Buffers' tag/length/value
shape but is not wire-compatible with protobuf: wirelet uses a fixed
canonical key order for maps, a `varint`-encoded discriminator for
sum types, and a fixed enumeration of wire-type codes (no group / SGROUP /
EGROUP / start-tag-end-tag types).

## Overview

Every field of a record is emitted as `<tag-varint> <payload>`.

- The **tag-varint** is a single base-128 varint whose low 3 bits encode
  the **wire type** and whose upper bits encode the **field tag**
  (a positive integer; tag 0 is forbidden).
- The **payload** layout depends on the wire type — see the table below.

A record (an instance of a `@WireFormat` struct) is the concatenation of
its fields' `<tag, payload>` pairs in declaration order. When that record
appears as a nested field of another record, the bytes are wrapped by a
varint length prefix (wire type `lengthDelimited`).

## Wire types

The 3-bit wire-type field in every tag varint is one of:

| Code | Name             | Used for                                                   |
|------|------------------|------------------------------------------------------------|
| 0    | varint           | `Int*` / `UInt*` / `Bool` / `@WireFormatEnum` raw          |
| 1    | fixed64          | `Double`, fixed-width 64-bit integers                      |
| 2    | length-delimited | `String` / `Data` / `Array` / `Dictionary` / nested struct / `@WireFormatChoice` |
| 5    | fixed32          | `Float`, fixed-width 32-bit integers                       |

Codes 3, 4, 6, 7 are unused and a reader MUST reject them with
`WireFormatError.unknownWireType`. There is no `groupStart` / `groupEnd`
escape hatch.

## Skipping unknown fields (O(1) per wire type)

A decoder that encounters an unknown tag can skip the field in constant
time relative to the wire type, without knowing the field's logical type:

| Wire type        | Skip strategy                                       |
|------------------|-----------------------------------------------------|
| varint           | read one varint, discard                            |
| fixed64          | advance reader 8 bytes                              |
| length-delimited | read one varint *N*, advance reader *N* bytes       |
| fixed32          | advance reader 4 bytes                              |

This O(1) skip is the reason the wire-type code is co-located with the
tag in every tag varint — it preserves forward-compat decode even when
appended fields use types the reader has never heard of.

The default decoder behaviour on unknown tags is configurable; today the
Swift runtime skips silently for forward-compat. A strict mode that
throws `WireFormatError.unknownTag(tag:wireType:)` is exposed for callers
that want to surface schema drift.

## Per-type encoding

### Integers

| Swift type                                          | Wire type | Payload                            |
|-----------------------------------------------------|-----------|------------------------------------|
| `UInt8`, `UInt16`, `UInt32`, `UInt64`, `UInt`       | varint    | unsigned LEB128                    |
| `Int8`, `Int16`, `Int32`, `Int64`, `Int`           | varint    | ZigZag → unsigned LEB128           |

ZigZag transform: `(n << 1) ^ (n >> 63)` (64-bit arithmetic, sign bit
broadcast). This keeps small negative numbers compact (`-1 → 1`,
`-2 → 3`, …) and keeps the wire type homogeneous (all signed and
unsigned integers share wire type `varint`).

A varint is at most 10 bytes (the 64-bit ceiling); readers MUST reject
varints longer than 10 bytes with `WireFormatError.varintOverflow`.

### Booleans

Wire type `varint`. Payload is the single byte `0x00` (false) or `0x01`
(true). A non-zero / non-one byte is still decoded as `true` to preserve
the protobuf convention.

### Floating-point

| Swift type | Wire type | Payload                                           |
|------------|-----------|---------------------------------------------------|
| `Float`    | fixed32   | 4-byte little-endian IEEE 754                     |
| `Double`   | fixed64   | 8-byte little-endian IEEE 754                     |

### Strings

Wire type `length-delimited`. Payload = `<varint utf8-byte-count>
<utf8-bytes>`. A reader MUST validate UTF-8 and throw
`WireFormatError.invalidUTF8` on malformed input.

### Bytes (`Data` / `ByteArray`)

Wire type `length-delimited`. Payload = `<varint byte-count> <bytes>`.

### Arrays

Wire type `length-delimited`. Payload = `<varint payload-byte-count>
<element-stream>` where `<element-stream>` is the concatenation of each
element's TLV encoding, tagged with its index + 1 (so the first element
is tag 1, the second is tag 2, …). The element's wire type is its own
type's `wireType`.

Empty arrays are encoded as a length-0 payload (`<0x00>`).

### Dictionaries (canonical key order)

Wire type `length-delimited`. Payload = `<varint entry-count>
<entry-stream>` where `<entry-stream>` is the concatenation of entries.
Each entry is `<K_payload> <V_payload>` — the key's full `encode(into:)`
output followed by the value's full `encode(into:)` output, with no
inner tags wrapping them. For primitive keys/values this is the bare
payload; for nested `@WireFormat` keys/values this includes their own
length prefix so each entry remains self-delimiting within the stream.

**Canonical order:** entries are sorted by encoded-key bytes
(lexicographic, byte-wise) before emission. This guarantees byte-identical
output between Swift and Kotlin for the same logical map. Decoders MUST
NOT rely on order — they accept any permutation.

### Nested `@WireFormat` struct

Wire type `length-delimited`. When emitted as a field of an enclosing
record, the parent writes `<tag-varint>` then the child's full
`encode(into:)` output — which itself begins with a `<varint
inner-length>` written by `writeLengthPrefixed`, so the child is
self-delimiting.

`encodePayload(into:)` writes only the body without the length prefix —
use it when the surrounding context already provides framing (e.g.
top-level encoding via `encodeToData`, or an in-place re-emit).

### `@WireFormatEnum`

Wire type = the enum's `RawValue.wireType`. For the canonical integer
raw (`UInt8`, the macro default) this is `varint`. The payload is just
the raw value, encoded by the raw type's own `encodePayload`. No tag
wraps the raw — the tag belongs to the enclosing field.

A reader that gets a raw value with no matching case throws
`WireFormatError.invalidCount(raw)`.

### `@WireFormatChoice` (sum type with associated values)

Wire type `length-delimited`. Payload layout:

```
<varint discriminator>      ← case's declaration-order index (0, 1, 2, …)
<TLV per-case associated values, tagged 1..N>
```

Cases without associated values encode as just the discriminator varint
inside the length-prefixed wrapper. A reader that gets a discriminator
outside the known case range throws
`WireFormatError.unknownChoiceDiscriminator`.

Adding a case at the end is forward-compatible (new wire → old reader)
only when the old reader explicitly relaxes the unknown-discriminator
check; reordering or removing cases is a breaking wire change.

## Tag assignment rules

- **Implicit tags** assign 1, 2, 3, … to stored properties in
  declaration order. The counter advances by 1 per implicit field,
  **skipping** any tag number that appears in the struct's reserved set
  ∪ the set of explicitly-assigned tags. The "skip" is a fill-gap
  semantic: an explicit tag does not push the counter past it, so a
  subsequent implicit property may receive a tag below the explicit
  value. This keeps implicit numbering deterministic but compact.
- **Explicit tags** are applied via `@WireFormatField(tag: N)` on a
  stored property. The value must be `> 0` and must not collide with
  another explicit tag or a reserved tag in the same struct.
- **Reserved tags** are declared on the struct via
  `@WireFormat(reservedTags: [...])`. No field may use them, and the
  implicit counter skips over them. Use this to retire a tag after a
  field is deleted — the tag MUST NEVER be reused for a new field, or
  old payloads will decode into wrong slots.
- **Tag 0** is reserved by the format; the macro rejects any field
  declaring `@WireFormatField(tag: 0)` at compile time.

## Worked example: `Point(x: -5, y: 17)`

Schema:

```swift
@WireFormat
struct Point {
    var x: Int32
    var y: Int32
}
```

Implicit tags: `x` → 1, `y` → 2. Both fields use wire type `varint`
(zigzag-varint signed integers).

Top-level `encodeToData()` calls `encode(into:)`, which wraps the body
in `writeLengthPrefixed`. Body emission:

```
writeTag(1, .varint)            = (1 << 3) | 0 = 8       → 0x08
writeZigZagVarint(-5)           ZigZag(-5) = 9           → 0x09
writeTag(2, .varint)            = (2 << 3) | 0 = 16      → 0x10
writeZigZagVarint(17)           ZigZag(17) = 34          → 0x22
```

Body = `08 09 10 22` (4 bytes).

The outer `writeLengthPrefixed` emits `<varint 4>` (one byte `04`)
followed by the body.

Final byte stream (5 bytes total):

```
04 08 09 10 22
```

Read top-to-bottom:

| Offset | Byte | Meaning                                                       |
|--------|------|---------------------------------------------------------------|
| 0      | 04   | outer length-prefix varint: body is 4 bytes                   |
| 1      | 08   | tag varint: (tag = 1, wireType = 0 / varint)                  |
| 2      | 09   | ZigZag-encoded `x = -5`                                       |
| 3      | 10   | tag varint: (tag = 2, wireType = 0 / varint)                  |
| 4      | 22   | ZigZag-encoded `y = 17`                                       |

A decoder reads the outer varint (4), takes a 4-byte slice, and inside
that slice reads two `(tag, payload)` pairs until `isAtEnd`. Trailing
bytes beyond the slice are tolerated at the top level — the
`init(decoding:)` convenience consumes only the prefixed bytes.

## Updating fixtures

Any change to the wire format — new wire type, change to ZigZag, change
to dictionary key ordering, change to varint length cap — invalidates
the cross-language conformance fixtures stored under
`kotlin/conformance-tests/fixtures/*.bin`. A wire-format-affecting PR
MUST regenerate those fixtures and include the regenerated bytes in the
same commit, so Kotlin's conformance suite continues to assert
byte-identical Swift output.

### Suite layout

```
Tests/ConformanceTests/                          Swift side
├── FixtureSchemas.swift                         @WireFormat declarations
├── GenerateFixtures.swift                       disabled-by-default regenerator
├── FixtureRunner.swift                          5 decode + re-encode tests
└── FixtureURL.swift                             #filePath-based fixture locator
kotlin/conformance-tests/                        Kotlin side
├── build.gradle.kts                             runs emit-wirelet-kotlin pre-compile
├── kotlin-codegen.json                          codegen config
├── src/main/kotlin/.../model/                   hand-authored data classes
├── src/test/kotlin/.../FixtureRunner.kt         5 decode + re-encode tests
└── fixtures/                                    .bin (Swift-encoded) + .json (answer key)
```

The `.json` companion files are human-readable answer keys committed
alongside the bytes. The runners do NOT load them — they're for
reviewers and for documenting what each `.bin` is supposed to represent.

### Regeneration workflow

1. Edit `Tests/ConformanceTests/FixtureSchemas.swift` (if the schemas
   themselves are changing — uncommon; usually a wire-format change
   only requires step 2 below).
2. Drop the `.disabled(...)` marker on `regenerateFixtures` in
   `Tests/ConformanceTests/GenerateFixtures.swift`.
3. `swift test --filter ConformanceTests.regenerateFixtures`.
4. Inspect the produced `.bin` files (`xxd` or a hex viewer); update
   the matching `.json` answer keys if values changed; restore the
   `.disabled(...)` marker.
5. Run both suites and confirm green:
   - `swift test --filter ConformanceTests`
   - `cd kotlin && ./gradlew :conformance-tests:test`
6. Commit `Tests/ConformanceTests/`, `kotlin/conformance-tests/fixtures/`,
   and any code changes in a single commit.

If only the Kotlin emission needs updating (no wire bytes change), step 3
is unnecessary — `./gradlew :conformance-tests:test` regenerates codecs
from `FixtureSchemas.swift` on every build via the `generateCodecs`
Exec task, then runs the decode tests against the existing fixtures.
