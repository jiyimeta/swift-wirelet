# Wirelet Observable Bridge — Phase 3: Kotlin runtime + Gradle plugin

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Kotlin-side artifact (`wirelet-observable-runtime`) that the Phase 2 emitter's generated `<Name>ViewModel.kt` files consume, plus an `observable { … }` DSL block in the existing `io.github.jiyimeta.wirelet` Gradle plugin that drives `generateWireletObservableViewModels<SourceSet>` tasks. End of Phase 3 a real Kotlin/Android project can compile the generated view-models against a published-locally `wirelet-observable-runtime`.

**Architecture:** Mirror the existing `:runtime` / `:gradle-plugin` shape. A new Gradle sub-module `kotlin/observable-runtime/` produces the `wirelet-observable-runtime` Maven artifact and exposes `WireletList.encode/decode` — the only runtime symbol the Phase 2 emitter references. The runtime takes `(T, BinaryWriter) -> Unit` / `(BinaryReader) -> T` function-typed parameters (passed as `TodoItemCodec::encodePayload` / `::decodePayload` method references from the emitted view-models), so no interface needs retrofitting onto `WireletKotlinEmitter`-produced codecs. The Gradle plugin gains a `WireletObservableSourceSet` container and a `GenerateWireletObservableViewModels` task class that forks `swift run … emit-wirelet-observable …` — same execution shape as the existing `GenerateWireletCodecs`. Functional tests use Gradle TestKit identically to the existing wireformat suite.

**Tech Stack:** Kotlin 1.9.22, Gradle 8.x, kotlin("jvm"), `java-gradle-plugin`, kotlinx.coroutines (compile-time API consumers reference; runtime artifact itself only needs reader/writer), JUnit Jupiter, Gradle TestKit. SwiftPM only via the forked `emit-wirelet-observable` CLI (already built in Phase 2). No new Swift code.

---

## File Structure

**Create:**
- `kotlin/observable-runtime/build.gradle.kts` — Kotlin JVM module, `wirelet-observable-runtime` Maven artifact, depends on `:runtime`.
- `kotlin/observable-runtime/src/main/kotlin/io/github/jiyimeta/wirelet/observable/WireletList.kt` — `WireletList` object with `encode(List<T>, (T, BinaryWriter) -> Unit): ByteArray` and `decode(ByteArray, (BinaryReader) -> T): List<T>` matching the Swift `WireletObservableJNI.encodeArray` / `decodeArray` wire format (varint count + per-element length-prefixed payload).
- `kotlin/observable-runtime/src/test/kotlin/io/github/jiyimeta/wirelet/observable/WireletListTest.kt` — round-trip tests + empty-list + 1k-element sanity.
- `kotlin/gradle-plugin/src/main/kotlin/io/github/jiyimeta/wirelet/gradle/WireletObservableSourceSet.kt` — `Named` DSL element for `observable { register(…) { … } }`.
- `kotlin/gradle-plugin/src/main/kotlin/io/github/jiyimeta/wirelet/gradle/GenerateWireletObservableViewModels.kt` — `@CacheableTask` that writes `observable-codegen.json` + forks `swift run … emit-wirelet-observable …`.
- `kotlin/gradle-plugin/src/functionalTest/kotlin/io/github/jiyimeta/wirelet/gradle/ObservableSourceSetTest.kt` — TestKit fixture: register an `observable` source set, assert `<Name>ViewModel.kt` lands in `${buildDir}/generated/wirelet/observable/<name>/kotlin/`.
- `kotlin/gradle-plugin/src/functionalTest/kotlin/io/github/jiyimeta/wirelet/gradle/ObservableAndCodecsCoexistTest.kt` — both `sources` and `observable` configured in the same project, both task chains run.

**Modify:**
- `kotlin/settings.gradle.kts` — `include(":observable-runtime")`.
- `kotlin/gradle-plugin/src/main/kotlin/io/github/jiyimeta/wirelet/gradle/WireletExtension.kt` — add `observable: NamedDomainObjectContainer<WireletObservableSourceSet>` + `observable(Action)` helper.
- `kotlin/gradle-plugin/src/main/kotlin/io/github/jiyimeta/wirelet/gradle/WireletPlugin.kt` — wire `extension.observable.all { registerObservableSourceSet(…) }`.
- `Sources/WireletObservableKotlinEmitter/Internal/ObservableKotlinTypeMap.swift` — change `WireletList.decode($1, \(codec))` → `WireletList.decode($1, \(codec)::decodePayload)` and `WireletList.encode($1, \(codec))` → `WireletList.encode($1, \(codec)::encodePayload)`. Phase 2 emitted call sites passed the codec singleton; the runtime API now takes method references so no `WireletElementCodec` interface needs to be retrofitted onto the `WireletKotlinEmitter`-produced codecs.
- `Tests/WireletObservableKotlinEmitterTests/Fixtures/TodoListViewModel.expected.kt` — re-bootstrap the golden after the emitter change (only the two `WireletList.decode`/`encode` lines change; the rest is unaffected). `CounterViewModel.expected.kt` has no array fields so it's untouched.

**Out of scope (future plans):**
- `examples/observable-counter/` Android example + emulator CI — Phase 4 plan.
- `kotlin.yml` / `examples.yml` matrix extension to include the observable artifact in CI — Phase 4 plan touches it alongside the example.
- `publish.yml` wiring `wirelet-observable-runtime` to GitHub Packages — Phase 5 plan (with the version bump to `v0.2.0`).
- README "Observable bridge" section — Phase 5 plan.
- Conformance fixture `observable_burst_v1.txt` — Phase 4 plan (paired with the emulator smoke).

---

## Phase 3A: Kotlin runtime artifact

### Task 1: Register the new Gradle sub-module

**Files:**
- Modify: `kotlin/settings.gradle.kts`

- [ ] **Step 1: Add the include**

Find the last `include(...)` line:

```kotlin
include(":gradle-plugin")
```

Insert immediately after:

```kotlin
include(":observable-runtime")
```

- [ ] **Step 2: Create the module directory + empty source tree**

Run:

```bash
mkdir -p kotlin/observable-runtime/src/main/kotlin/io/github/jiyimeta/wirelet/observable
mkdir -p kotlin/observable-runtime/src/test/kotlin/io/github/jiyimeta/wirelet/observable
```

- [ ] **Step 3: Verify settings still parse**

Run: `kotlin/gradlew -p kotlin help -q`
Expected: completes with exit 0 and lists `:observable-runtime` under `Existing projects` when `kotlin/gradlew -p kotlin projects` is run (next sub-step).

Run: `kotlin/gradlew -p kotlin projects`
Expected: output contains `+--- Project ':observable-runtime'`. (Gradle reports the module even before its build script exists — Step 4 adds it.)

- [ ] **Step 4: Commit (settings-only intermediate state)**

```bash
git add kotlin/settings.gradle.kts
git commit -m "build(observable): register :observable-runtime sub-module in kotlin settings"
```

### Task 2: Add the `observable-runtime` build script

**Files:**
- Create: `kotlin/observable-runtime/build.gradle.kts`

- [ ] **Step 1: Write the build script**

Create `kotlin/observable-runtime/build.gradle.kts` with:

```kotlin
plugins {
    kotlin("jvm")
    `maven-publish`
}

group = "io.github.jiyimeta"
version = (findProperty("wireletVersion") as String?) ?: "0.0.0-SNAPSHOT"

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
    withSourcesJar()
}

dependencies {
    // BinaryReader / BinaryWriter live in :runtime. WireletList delegates to
    // them — same wire format as the in-struct array codec produced by
    // emit-wirelet-kotlin.
    api(project(":runtime"))

    testImplementation(kotlin("test"))
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
}

tasks.test {
    useJUnitPlatform()
}

publishing {
    publications {
        create<MavenPublication>("observableRuntime") {
            from(components["java"])
            artifactId = "wirelet-observable-runtime"
        }
    }
    repositories {
        maven {
            name = "GitHubPackages"
            url = uri("https://maven.pkg.github.com/jiyimeta/swift-wirelet")
            credentials {
                username = System.getenv("GITHUB_ACTOR")
                password = System.getenv("GITHUB_TOKEN")
            }
        }
    }
}
```

`api(project(":runtime"))` (not `implementation`) so consumers of `wirelet-observable-runtime` transitively see `BinaryReader` / `BinaryWriter` — the generated view-model code references them indirectly through `WireletList.decode { TodoItemCodec.decodePayload(it) }` where `it` is a `BinaryReader`. Marking as `api` keeps the consumer's POM straight.

The runtime intentionally has **no kotlinx.coroutines or AndroidX dependency** in v0.1: the Phase 2 emitted view-models reference `kotlinx.coroutines.flow.*` and `androidx.lifecycle.*` directly, and the consumer's Android module supplies those via its own `dependencies` block. Pulling AndroidX into a Maven artifact published as `kotlin("jvm")` (not `com.android.library`) would force JVM-only consumers to pull a moot dependency. The spec confirms this split: `wirelet-runtime` stays coroutines-free, and consumers add AndroidX themselves.

- [ ] **Step 2: Verify the module builds (no sources yet)**

Run: `kotlin/gradlew -p kotlin :observable-runtime:compileKotlin -q`
Expected: `BUILD SUCCESSFUL`. Compiles an empty source set — fine.

- [ ] **Step 3: Commit**

```bash
git add kotlin/observable-runtime/build.gradle.kts
git commit -m "build(observable): add kotlin/observable-runtime module skeleton"
```

### Task 3: Implement `WireletList` + unit tests (TDD)

**Files:**
- Create: `kotlin/observable-runtime/src/test/kotlin/io/github/jiyimeta/wirelet/observable/WireletListTest.kt`
- Create: `kotlin/observable-runtime/src/main/kotlin/io/github/jiyimeta/wirelet/observable/WireletList.kt`

The wire format mirrors `WireletObservableJNI.encodeArray` on the Swift side:

```
[ varint count ][ len₀ + payload₀ ][ len₁ + payload₁ ] … [ lenₙ₋₁ + payloadₙ₋₁ ]
```

The runtime exposes a method-reference-friendly API. Generated view-model code passes `TodoItemCodec::decodePayload` (a `(BinaryReader) -> TodoItem` reference) and `TodoItemCodec::encodePayload` (a `(TodoItem, BinaryWriter) -> Unit` reference). Phase 1 plan / Phase 2 emit already produces these method signatures on every `@WireFormat`-generated codec object.

- [ ] **Step 1: Write the failing test**

Create `kotlin/observable-runtime/src/test/kotlin/io/github/jiyimeta/wirelet/observable/WireletListTest.kt` with:

```kotlin
package io.github.jiyimeta.wirelet.observable

import io.github.jiyimeta.wirelet.BinaryReader
import io.github.jiyimeta.wirelet.BinaryWriter
import kotlin.test.Test
import kotlin.test.assertEquals

class WireletListTest {

    /** Toy WireFormat-style element used by the round-trip tests. */
    private data class Pair2(val a: Int, val b: Int)

    private fun encodePair(value: Pair2, w: BinaryWriter) {
        w.writeTag(1, io.github.jiyimeta.wirelet.WireType.VARINT)
        w.writeZigZagVarint(value.a.toLong())
        w.writeTag(2, io.github.jiyimeta.wirelet.WireType.VARINT)
        w.writeZigZagVarint(value.b.toLong())
    }

    private fun decodePair(r: BinaryReader): Pair2 {
        var a: Int? = null
        var b: Int? = null
        while (r.remaining > 0) {
            val (tag, wt) = r.readTag()
            when (tag) {
                1 -> a = r.readZigZagVarint().toInt()
                2 -> b = r.readZigZagVarint().toInt()
                else -> r.skipUnknownField(wt)
            }
        }
        return Pair2(a ?: error("missing field 1"), b ?: error("missing field 2"))
    }

    @Test
    fun roundTripPreservesOrder() {
        val original = listOf(Pair2(1, -2), Pair2(3, 4), Pair2(-5, 6))
        val bytes = WireletList.encode(original, ::encodePair)
        val decoded = WireletList.decode(bytes, ::decodePair)
        assertEquals(original, decoded)
    }

    @Test
    fun roundTripEmptyList() {
        val bytes = WireletList.encode(emptyList<Pair2>(), ::encodePair)
        // Empty payload after varint(0): single zero byte.
        assertEquals(1, bytes.size)
        assertEquals(0.toByte(), bytes[0])
        val decoded = WireletList.decode(bytes, ::decodePair)
        assertEquals(emptyList(), decoded)
    }

    @Test
    fun thousandElementRoundTrip() {
        val original = (0 until 1_000).map { Pair2(it, it * 2) }
        val bytes = WireletList.encode(original, ::encodePair)
        val decoded = WireletList.decode(bytes, ::decodePair)
        assertEquals(original, decoded)
        assertEquals(1_000, decoded.size)
    }

    @Test
    fun decodeIsTolerantOfUnknownTrailingTagsInPayload() {
        // Manually craft a payload whose Pair2 record has an extra tag-3 field
        // that decodePair must skip.
        val outer = BinaryWriter()
        outer.writeVarint(1L)
        outer.writeLengthPrefixed {
            writeTag(1, io.github.jiyimeta.wirelet.WireType.VARINT)
            writeZigZagVarint(7L)
            writeTag(2, io.github.jiyimeta.wirelet.WireType.VARINT)
            writeZigZagVarint(8L)
            // Unknown extra field — must be skipped, not error.
            writeTag(99, io.github.jiyimeta.wirelet.WireType.VARINT)
            writeZigZagVarint(0L)
        }
        val decoded = WireletList.decode(outer.toByteArray(), ::decodePair)
        assertEquals(listOf(Pair2(7, 8)), decoded)
    }
}
```

- [ ] **Step 2: Run the test, confirm it fails**

Run: `kotlin/gradlew -p kotlin :observable-runtime:test -q`
Expected: FAIL with `unresolved reference: WireletList`.

- [ ] **Step 3: Implement `WireletList`**

Create `kotlin/observable-runtime/src/main/kotlin/io/github/jiyimeta/wirelet/observable/WireletList.kt` with:

```kotlin
package io.github.jiyimeta.wirelet.observable

import io.github.jiyimeta.wirelet.BinaryReader
import io.github.jiyimeta.wirelet.BinaryWriter

/**
 * Wire-format helpers for `Array<T: WireFormat>` properties bridged through
 * `@WireletObservable`. Mirrors `WireletObservableJNI.encodeArray` /
 * `decodeArray` on the Swift side.
 *
 * On the wire:
 *
 *     [ varint count ]
 *     [ len₀ + payload₀ ]
 *     [ len₁ + payload₁ ]
 *     …
 *
 * Each element is length-delimited so [decode] / [encode] can stream a
 * heterogeneous count without buffering. The `payload` portion is whatever
 * the codec's `decodePayload(BinaryReader)` consumes / `encodePayload(value,
 * BinaryWriter)` writes — i.e. the same payload a struct codec would emit
 * inside its own outer length-prefixed block.
 *
 * Method-reference call sites:
 *
 *     val items: List<TodoItem> = WireletList.decode(bytes, TodoItemCodec::decodePayload)
 *     val bytes: ByteArray = WireletList.encode(items, TodoItemCodec::encodePayload)
 *
 * Passing function references rather than a `WireletElementCodec` interface
 * means the existing `WireletKotlinEmitter`-produced codec objects do not
 * need a retrofitted supertype.
 */
object WireletList {
    fun <T> decode(bytes: ByteArray, decodePayload: (BinaryReader) -> T): List<T> {
        val r = BinaryReader(bytes)
        val count = r.readVarint().toInt()
        return List(count) { r.readLengthPrefixed { decodePayload(it) } }
    }

    fun <T> encode(value: List<T>, encodePayload: (T, BinaryWriter) -> Unit): ByteArray {
        val w = BinaryWriter()
        w.writeVarint(value.size.toLong())
        for (element in value) {
            w.writeLengthPrefixed { encodePayload(element, this) }
        }
        return w.toByteArray()
    }
}
```

- [ ] **Step 4: Run the tests, confirm pass**

Run: `kotlin/gradlew -p kotlin :observable-runtime:test -q`
Expected: 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add kotlin/observable-runtime/src/main/kotlin/io/github/jiyimeta/wirelet/observable/WireletList.kt \
        kotlin/observable-runtime/src/test/kotlin/io/github/jiyimeta/wirelet/observable/WireletListTest.kt
git commit -m "feat(observable): add WireletList encode/decode in wirelet-observable-runtime"
```

### Task 4: Re-target observable emitter to method-reference codec args

**Files:**
- Modify: `Sources/WireletObservableKotlinEmitter/Internal/ObservableKotlinTypeMap.swift`
- Modify: `Tests/WireletObservableKotlinEmitterTests/Fixtures/TodoListViewModel.expected.kt`

The Phase 2 emitter produced `WireletList.decode($1, TodoItemCodec)`, passing the codec singleton. The runtime built in Task 3 takes method references instead, so update the templates. This is the only change required to bridge the Phase 2 emit to the Phase 3 runtime — no retrofit of `WireletKotlinEmitter` and no churn on the four wireformat golden fixtures.

- [ ] **Step 1: Update the type-map templates**

Open `Sources/WireletObservableKotlinEmitter/Internal/ObservableKotlinTypeMap.swift`. Find the case branch handling `wireFormatArray(elementTypeName:)`. The two template strings to change are:

Before:

```swift
decodeTemplate: "WireletList.decode($1, \(codec))",
encodeTemplate: "WireletList.encode($1, \(codec))",
```

After:

```swift
decodeTemplate: "WireletList.decode($1, \(codec)::decodePayload)",
encodeTemplate: "WireletList.encode($1, \(codec)::encodePayload)",
```

Both edits land in the same case branch — the strings are unique, so a single `Edit` per template suffices.

- [ ] **Step 2: Update the TodoListViewModel golden**

Open `Tests/WireletObservableKotlinEmitterTests/Fixtures/TodoListViewModel.expected.kt`. There are exactly four lines that change:

Before (line 32, decode track call):

```kotlin
        WireletList.decode(nativeItemsTrack(nativePtr, Runnable {
```

After:

```kotlin
        WireletList.decode(nativeItemsTrack(nativePtr, Runnable {
```

— this line is *unchanged*. The change is on the closing argument:

Before (line 36):

```kotlin
        }), TodoItemCodec)
```

After:

```kotlin
        }), TodoItemCodec::decodePayload)
```

Before (line 60, encode setter call):

```kotlin
        nativeItemsSet(nativePtr, WireletList.encode(value, TodoItemCodec))
```

After:

```kotlin
        nativeItemsSet(nativePtr, WireletList.encode(value, TodoItemCodec::encodePayload))
```

Apply both edits exactly. No other lines move.

- [ ] **Step 3: Run the observable emitter test suite, confirm pass**

Run: `swift test --filter WireletObservableKotlinEmitterTests`
Expected: both `counterEmits…` and `todoListEmits…` golden tests pass.

If only `todoList…` fails with a string mismatch, the live `actual` output printed by `assertEquals` is the source of truth — copy any remaining whitespace deltas into the fixture and re-run until clean.

- [ ] **Step 4: Run the CLI integration tests, confirm pass**

Run: `swift test --filter EmitWireletObservableTests`
Expected: `cliEmitsTodoListViewModel` and `cliIncludePackageFiltersOutput` both pass. (The CLI bootstraps off the emitter so the golden change propagates automatically.)

- [ ] **Step 5: Commit**

```bash
git add Sources/WireletObservableKotlinEmitter/Internal/ObservableKotlinTypeMap.swift \
        Tests/WireletObservableKotlinEmitterTests/Fixtures/TodoListViewModel.expected.kt
git commit -m "refactor(observable): emit WireletList codec args as ::decodePayload / ::encodePayload references"
```

---

## Phase 3B: Gradle plugin `observable` DSL

### Task 5: Add `WireletObservableSourceSet` DSL element

**Files:**
- Create: `kotlin/gradle-plugin/src/main/kotlin/io/github/jiyimeta/wirelet/gradle/WireletObservableSourceSet.kt`

Mirror the shape of `WireletSourceSet`. The observable codegen config does not need `serializationPackage` (the generated view-models do not reference `BinaryReader` / `BinaryWriter` directly — they go through `WireletList`), does not need `emitModels` (observable codegen never emits domain types), does not need `modelPackage` (resolved from the codec package via existing emitter logic), and the `nameTransform` knob is fixed at identity for v0.1.

- [ ] **Step 1: Write the source file**

Create `kotlin/gradle-plugin/src/main/kotlin/io/github/jiyimeta/wirelet/gradle/WireletObservableSourceSet.kt` with:

```kotlin
package io.github.jiyimeta.wirelet.gradle

import org.gradle.api.Named
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.provider.Property
import org.gradle.api.provider.SetProperty
import javax.inject.Inject

/**
 * One observable-codegen source set declared inside the
 * `wirelet { observable { ... } }` container. Each source set produces a
 * single `GenerateWireletObservableViewModels<Name>` task that runs the
 * `emit-wirelet-observable` CLI against `schemaPaths` and writes generated
 * `<Name>ViewModel.kt` into
 * `${buildDir}/generated/wirelet/observable/<name>/kotlin`.
 *
 * v1 limitation: `schemaPaths` must resolve to exactly one directory — the
 * underlying CLI takes a single `--source` argument.
 */
abstract class WireletObservableSourceSet @Inject constructor(
    private val sourceSetName: String,
) : Named {
    override fun getName(): String = sourceSetName

    /**
     * Directories scanned for `@WireletObservable` + `@Observable` Swift
     * class declarations. v1: exactly one entry.
     */
    abstract val schemaPaths: ConfigurableFileCollection

    /**
     * Kotlin package the generated `<Name>ViewModel.kt` files land under.
     * Required.
     */
    abstract val viewModelPackage: Property<String>

    /**
     * Kotlin package the model data classes live under. Required when any
     * `@WireletObservable` view-model has `@WireFormat` struct properties —
     * the generated view-model imports `<modelPackage>.<Name>` for each.
     */
    abstract val modelPackage: Property<String>

    /**
     * Kotlin package containing the per-`@WireFormat` codec objects.
     * Required when any `@WireletObservable` view-model has `@WireFormat`
     * struct properties — the generated view-model imports
     * `<codecPackage>.<Name>Codec` for each.
     */
    abstract val codecPackage: Property<String>

    /**
     * Kotlin package containing `WireletList` (and any future runtime
     * helpers). Defaults to `io.github.jiyimeta.wirelet.observable` — the
     * package wirelet-observable-runtime publishes under.
     */
    abstract val runtimePackage: Property<String>

    /**
     * Name of the `.so` library the generated companion object loads via
     * `System.loadLibrary(...)`. Required — there is no sensible default
     * because the consumer chooses the JNI library name.
     */
    abstract val libraryName: Property<String>

    /**
     * Filter: when non-empty, only view-models whose resolved Kotlin
     * package exactly matches one of these entries are written. Mirrors
     * the `--include-package` CLI flag.
     */
    abstract val includePackages: SetProperty<String>
}
```

- [ ] **Step 2: Verify it compiles**

Run: `kotlin/gradlew -p kotlin :gradle-plugin:compileKotlin -q`
Expected: `BUILD SUCCESSFUL`. No tests yet.

- [ ] **Step 3: Commit**

```bash
git add kotlin/gradle-plugin/src/main/kotlin/io/github/jiyimeta/wirelet/gradle/WireletObservableSourceSet.kt
git commit -m "feat(observable): add WireletObservableSourceSet DSL container element"
```

### Task 6: Extend `WireletExtension` with the `observable` container

**Files:**
- Modify: `kotlin/gradle-plugin/src/main/kotlin/io/github/jiyimeta/wirelet/gradle/WireletExtension.kt`

- [ ] **Step 1: Add the container + action helper**

Open `WireletExtension.kt`. After the existing `sources(...)` action helper, before the closing brace, append:

```kotlin
    /** Generation source sets for `@WireletObservable` view-models. */
    abstract val observable: NamedDomainObjectContainer<WireletObservableSourceSet>

    /** Configure-by-name shorthand for `observable { ... }`. */
    fun observable(configure: Action<NamedDomainObjectContainer<WireletObservableSourceSet>>) {
        configure.execute(observable)
    }
```

The result should look like:

```kotlin
abstract class WireletExtension {
    abstract val swiftPackagePath: DirectoryProperty
    abstract val sources: NamedDomainObjectContainer<WireletSourceSet>
    fun sources(configure: Action<NamedDomainObjectContainer<WireletSourceSet>>) {
        configure.execute(sources)
    }

    abstract val observable: NamedDomainObjectContainer<WireletObservableSourceSet>
    fun observable(configure: Action<NamedDomainObjectContainer<WireletObservableSourceSet>>) {
        configure.execute(observable)
    }
}
```

(Comments are preserved; existing prose between properties stays as-is.)

- [ ] **Step 2: Verify it compiles**

Run: `kotlin/gradlew -p kotlin :gradle-plugin:compileKotlin -q`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 3: Commit**

```bash
git add kotlin/gradle-plugin/src/main/kotlin/io/github/jiyimeta/wirelet/gradle/WireletExtension.kt
git commit -m "feat(observable): expose observable NamedDomainObjectContainer on WireletExtension"
```

### Task 7: Add `GenerateWireletObservableViewModels` task

**Files:**
- Create: `kotlin/gradle-plugin/src/main/kotlin/io/github/jiyimeta/wirelet/gradle/GenerateWireletObservableViewModels.kt`

This task mirrors `GenerateWireletCodecs`: write an `observable-codegen.json` config in `temporaryDir`, fork `swift run --package-path <swiftPackagePath> emit-wirelet-observable --config <json> --source <dir> --output <outputDir>`, append `--include-package` for every filter entry. The CLI signature is identical to `emit-wirelet-kotlin` (Phase 2 made sure of that).

- [ ] **Step 1: Write the task class**

Create `kotlin/gradle-plugin/src/main/kotlin/io/github/jiyimeta/wirelet/gradle/GenerateWireletObservableViewModels.kt` with:

```kotlin
package io.github.jiyimeta.wirelet.gradle

import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.FileTree
import org.gradle.api.provider.Property
import org.gradle.api.provider.SetProperty
import org.gradle.api.tasks.CacheableTask
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputFiles
import org.gradle.api.tasks.Internal
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction
import org.gradle.process.ExecOperations
import javax.inject.Inject

/**
 * Generates `<Name>ViewModel.kt` files for `@WireletObservable` declarations
 * by writing an `observable-codegen.json` config file in the task's
 * temporary directory and forking `swift run --package-path
 * <swiftPackagePath> emit-wirelet-observable --config <json> --source <dir>
 * --output <outputDir>`. Honours `--include-package` filters via the CLI.
 *
 * Marked `@CacheableTask`: outputs are pure functions of inputs (schema
 * sources + CLI source files + config inputs) so build cache works.
 */
@CacheableTask
abstract class GenerateWireletObservableViewModels @Inject constructor(
    private val execOperations: ExecOperations,
) : DefaultTask() {

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val schemaPaths: ConfigurableFileCollection

    /**
     * Filesystem location of the wirelet Swift package — used at exec time
     * to fork `swift run --package-path …`. Marked `@Internal` for the same
     * reason as in `GenerateWireletCodecs`: `swift run` mutates `.build/` /
     * `.swiftpm/` on every invocation, defeating UP-TO-DATE checks. The
     * version-tracked subset is fingerprinted through [cliSourceTree].
     */
    @get:Internal
    abstract val swiftPackagePath: DirectoryProperty

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    val cliSourceTree: FileTree
        get() = swiftPackagePath.asFileTree.matching {
            include("Sources/**")
            include("Package.swift")
        }

    @get:Input abstract val viewModelPackage: Property<String>
    @get:Input abstract val modelPackage: Property<String>
    @get:Input abstract val codecPackage: Property<String>
    @get:Input abstract val runtimePackage: Property<String>
    @get:Input abstract val libraryName: Property<String>
    @get:Input abstract val includePackages: SetProperty<String>

    @get:OutputDirectory abstract val outputDir: DirectoryProperty

    @TaskAction
    fun generate() {
        val schemaDir = schemaPaths.files.singleOrNull()
            ?: throw GradleException(
                "wirelet observable: schemaPaths must resolve to exactly one " +
                    "directory (got ${schemaPaths.files.size}). Multi-path " +
                    "support is deferred to a later release."
            )
        if (!schemaDir.isDirectory) {
            throw GradleException(
                "wirelet observable: schemaPaths entry is not a directory: $schemaDir"
            )
        }

        val configFile = temporaryDir.resolve("observable-codegen.json")
        configFile.writeText(buildCodegenConfigJson())

        val out = outputDir.get().asFile
        out.mkdirs()

        val args = mutableListOf(
            "run", "--package-path", swiftPackagePath.get().asFile.absolutePath,
            "emit-wirelet-observable",
            "--config", configFile.absolutePath,
            "--source", schemaDir.absolutePath,
            "--output", out.absolutePath,
        )
        for (pkg in includePackages.get()) {
            args += "--include-package"
            args += pkg
        }

        execOperations.exec {
            commandLine("swift", *args.toTypedArray())
        }
    }

    private fun buildCodegenConfigJson(): String {
        val vm = viewModelPackage.get()
        val model = modelPackage.get()
        val codec = codecPackage.get()
        val rt = runtimePackage.get()
        val lib = libraryName.get()
        return """
            {
              "viewModelPackage": ${quote(vm)},
              "modelPackage": ${quote(model)},
              "codecPackage": ${quote(codec)},
              "runtimePackage": ${quote(rt)},
              "libraryName": ${quote(lib)},
              "nameTransform": { "identity": true }
            }
        """.trimIndent()
    }

    private fun quote(s: String): String {
        val escaped = s.replace("\\", "\\\\").replace("\"", "\\\"")
        return "\"$escaped\""
    }
}
```

Important — the JSON keys must match `ObservableCodegenConfig`'s `Decodable` field names exactly. If a Phase 2 commit changed any of those names (e.g. `viewModelPackage` → `vmPackage`), use the actual on-disk Swift names. Verify against `Sources/WireletObservableKotlinEmitter/ObservableCodegenConfig.swift` before running the first test — that file is the source of truth.

- [ ] **Step 2: Cross-check the JSON schema**

Run: `grep -n "let .*: String\|let .*: \\[" Sources/WireletObservableKotlinEmitter/ObservableCodegenConfig.swift`
Expected: prints the property declarations. Confirm each `Property` you wrote in `buildCodegenConfigJson` lines up with a `let` declaration that has the same name. If any drift, edit the JSON keys (not the Swift) and re-run.

- [ ] **Step 3: Verify it compiles**

Run: `kotlin/gradlew -p kotlin :gradle-plugin:compileKotlin -q`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 4: Commit**

```bash
git add kotlin/gradle-plugin/src/main/kotlin/io/github/jiyimeta/wirelet/gradle/GenerateWireletObservableViewModels.kt
git commit -m "feat(observable): add GenerateWireletObservableViewModels Gradle task"
```

### Task 8: Wire the `observable` container into `WireletPlugin`

**Files:**
- Modify: `kotlin/gradle-plugin/src/main/kotlin/io/github/jiyimeta/wirelet/gradle/WireletPlugin.kt`

- [ ] **Step 1: Add the registration hook**

Open `WireletPlugin.kt`. In `apply(target)`, after the existing `extension.sources.all { … }` line, append:

```kotlin
        extension.observable.all { registerObservableSourceSet(target, extension, this) }
```

Then add a new private method below `registerSourceSet`:

```kotlin
    private fun registerObservableSourceSet(
        project: Project,
        extension: WireletExtension,
        entry: WireletObservableSourceSet,
    ) {
        val taskName = "generateWireletObservableViewModels${
            entry.name.replaceFirstChar { it.uppercaseChar() }
        }"
        val task = project.tasks.register(
            taskName,
            GenerateWireletObservableViewModels::class.java,
        ) {
            group = "wirelet"
            description = "Generates @WireletObservable view-models for source set '${entry.name}'."
            schemaPaths.from(entry.schemaPaths)
            swiftPackagePath.set(extension.swiftPackagePath)
            viewModelPackage.set(entry.viewModelPackage)
            modelPackage.set(entry.modelPackage)
            codecPackage.set(entry.codecPackage)
            runtimePackage.set(
                entry.runtimePackage.orElse("io.github.jiyimeta.wirelet.observable"),
            )
            libraryName.set(entry.libraryName)
            includePackages.set(entry.includePackages)
            outputDir.set(
                project.layout.buildDirectory.dir(
                    "generated/wirelet/observable/${entry.name}/kotlin",
                ),
            )
        }

        project.plugins.withId("org.jetbrains.kotlin.jvm") {
            wireOutputIntoKotlinSourceSet(project, entry.name, task)
        }
        // Same wiring for Android Gradle plugin consumers — they register
        // their Kotlin source sets through the Android extension, which the
        // Kotlin JVM plugin id won't necessarily resolve, so also listen for
        // the Kotlin Android plugin id.
        project.plugins.withId("org.jetbrains.kotlin.android") {
            wireOutputIntoKotlinSourceSet(project, entry.name, task)
        }
    }

    private fun wireOutputIntoKotlinSourceSet(
        project: org.gradle.api.Project,
        sourceSetName: String,
        task: org.gradle.api.tasks.TaskProvider<GenerateWireletObservableViewModels>,
    ) {
        val sourceSets = project.extensions.findByType(
            org.gradle.api.tasks.SourceSetContainer::class.java,
        ) ?: return
        val kotlinSourceSet = sourceSets.findByName(sourceSetName) ?: return
        val kotlinDirs = kotlinSourceSet.extensions.findByName("kotlin")
            as? org.gradle.api.file.SourceDirectorySet
        kotlinDirs?.srcDir(task.flatMap { it.outputDir })

        val compileTaskName = if (sourceSetName == "main") {
            "compileKotlin"
        } else {
            "compile${sourceSetName.replaceFirstChar { it.uppercaseChar() }}Kotlin"
        }
        project.tasks.matching { it.name == compileTaskName }
            .configureEach { dependsOn(task) }
    }
```

Notes:

- The fully-qualified `org.gradle.api.*` imports in `wireOutputIntoKotlinSourceSet` mirror the style already used in `registerSourceSet` (the existing method also reaches into `SourceSetContainer` / `SourceDirectorySet`). Add top-of-file imports if the existing file already has them; otherwise leaving them inline is fine.
- Existing imports at the top of the file (`org.gradle.api.file.SourceDirectorySet`, `org.gradle.api.tasks.SourceSetContainer`) already cover the same types referenced from `registerSourceSet` — prefer using those by reference rather than re-qualifying. The inline `org.gradle.api.tasks.TaskProvider` import the method signature needs is the only new import to add.

If preferred, add to the imports block at the top:

```kotlin
import org.gradle.api.tasks.TaskProvider
```

…and drop the inline qualifier from the parameter type. Functionally identical.

- [ ] **Step 2: Verify it compiles**

Run: `kotlin/gradlew -p kotlin :gradle-plugin:compileKotlin -q`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 3: Commit**

```bash
git add kotlin/gradle-plugin/src/main/kotlin/io/github/jiyimeta/wirelet/gradle/WireletPlugin.kt
git commit -m "feat(observable): register observable source sets in WireletPlugin"
```

### Task 9: Functional test — single observable source set

**Files:**
- Create: `kotlin/gradle-plugin/src/functionalTest/kotlin/io/github/jiyimeta/wirelet/gradle/ObservableSourceSetTest.kt`

- [ ] **Step 1: Write the failing test**

Create `ObservableSourceSetTest.kt` with:

```kotlin
package io.github.jiyimeta.wirelet.gradle

import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ObservableSourceSetTest {
    @Test
    fun generatesViewModelKotlinForSimpleCounter(@TempDir tempDir: File) {
        layoutFixture(
            dir = tempDir,
            extraBuildScript = """
                wirelet {
                    swiftPackagePath.set(file(${'"'}${wireletRepoRoot.absolutePath}${'"'}))
                    observable {
                        register("main") {
                            schemaPaths.from(file("schema"))
                            viewModelPackage.set("com.example.fixture.viewmodels")
                            modelPackage.set("com.example.fixture.model")
                            codecPackage.set("com.example.fixture.codec")
                            libraryName.set("CounterJNI")
                        }
                    }
                }
                // Avoid resolving the runtime artifact (not on Maven yet);
                // we only care that the generate task itself succeeds and
                // wires output into the kotlin source set's srcDirs.
                tasks.named("compileKotlin") { enabled = false }
            """.trimIndent(),
        )
        writeSchemaFile(
            dir = tempDir,
            relativePath = "schema/CounterVM.swift",
            content = """
                import Observation
                import WireletObservable

                @WireletObservable
                @Observable
                public final class CounterVM {
                    public var count: Int32 = 0
                    public init() {}
                }
            """.trimIndent(),
        )

        val result = runner(tempDir, "generateWireletObservableViewModelsMain").build()

        assertEquals(
            TaskOutcome.SUCCESS,
            result.task(":generateWireletObservableViewModelsMain")?.outcome,
            "observable generate task did not run to SUCCESS",
        )
        val expectedVM = tempDir.resolve(
            "build/generated/wirelet/observable/main/kotlin/" +
                "com/example/fixture/viewmodels/CounterViewModel.kt",
        )
        assertTrue(expectedVM.exists(), "view-model file not written at $expectedVM")
        val content = expectedVM.readText()
        assertTrue(
            content.contains("class CounterViewModel internal constructor"),
            "expected generated view-model class; got:\n$content",
        )
        assertTrue(
            content.contains("System.loadLibrary(\"CounterJNI\")"),
            "library name not propagated to generated companion; got:\n$content",
        )
    }
}
```

- [ ] **Step 2: Run the test, confirm it fails**

Run: `kotlin/gradlew -p kotlin :gradle-plugin:functionalTest --tests ObservableSourceSetTest -q`
Expected: FAIL — typically because the `observable { register("main") { ... } }` DSL needs the prior tasks committed and the wiring picked up by the in-process plugin classpath. If the test errors with `Unresolved reference: observable`, re-run `kotlin/gradlew -p kotlin :gradle-plugin:compileKotlin` then re-run the functional test (the TestKit classpath caches compiled output).

If the test runs and fails with `Project ':' could not find observable source set`, that points at a real wiring bug — debug `WireletPlugin.apply` (Task 8 wiring missed).

- [ ] **Step 3: If failing for the expected "DSL wires but CLI fails" reason, surface the actual CLI failure**

Re-run with `--info` to see the CLI stderr:

```bash
kotlin/gradlew -p kotlin :gradle-plugin:functionalTest \
    --tests ObservableSourceSetTest --info
```

If the CLI complains about a JSON key the emitter doesn't recognize, the JSON in `GenerateWireletObservableViewModels.buildCodegenConfigJson()` is out of sync with `ObservableCodegenConfig` — fix the JSON keys and re-run.

- [ ] **Step 4: Iterate to green**

Keep adjusting until the test reports SUCCESS. The most common remaining failure mode is a missing `swift` binary on the test runner's PATH; in CI that's handled by the existing `swift.yml` matrix, but locally make sure `which swift` resolves before re-running.

- [ ] **Step 5: Commit**

```bash
git add kotlin/gradle-plugin/src/functionalTest/kotlin/io/github/jiyimeta/wirelet/gradle/ObservableSourceSetTest.kt
git commit -m "test(observable): TestKit smoke for observable source set codegen"
```

### Task 10: Functional test — wireformat + observable coexist

**Files:**
- Create: `kotlin/gradle-plugin/src/functionalTest/kotlin/io/github/jiyimeta/wirelet/gradle/ObservableAndCodecsCoexistTest.kt`

Verifies that a single Gradle project registering both `sources` (wireformat codecs) and `observable` (view-models) produces both task chains, with disjoint output directories so neither overwrites the other.

- [ ] **Step 1: Write the failing test**

```kotlin
package io.github.jiyimeta.wirelet.gradle

import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ObservableAndCodecsCoexistTest {
    @Test
    fun bothTaskChainsRunWithDisjointOutputs(@TempDir tempDir: File) {
        layoutFixture(
            dir = tempDir,
            extraBuildScript = """
                wirelet {
                    swiftPackagePath.set(file(${'"'}${wireletRepoRoot.absolutePath}${'"'}))
                    sources {
                        register("main") {
                            schemaPaths.from(file("schema"))
                            codecPackage.set("com.example.fixture.codec")
                            modelPackage.set("com.example.fixture.model")
                            emitModels.set(true)
                        }
                    }
                    observable {
                        register("main") {
                            schemaPaths.from(file("schema"))
                            viewModelPackage.set("com.example.fixture.viewmodels")
                            modelPackage.set("com.example.fixture.model")
                            codecPackage.set("com.example.fixture.codec")
                            libraryName.set("CounterJNI")
                        }
                    }
                }
                tasks.named("compileKotlin") { enabled = false }
            """.trimIndent(),
        )
        // CounterVM is a valid @WireletObservable AND a plain Swift class —
        // the wireformat emitter ignores it. A separate Point struct is the
        // only @WireFormat producer.
        writeSchemaFile(
            dir = tempDir,
            relativePath = "schema/CounterVM.swift",
            content = """
                import Observation
                import WireletObservable

                @WireletObservable
                @Observable
                public final class CounterVM {
                    public var count: Int32 = 0
                    public init() {}
                }
            """.trimIndent(),
        )
        writeSchemaFile(
            dir = tempDir,
            relativePath = "schema/Point.swift",
            content = """
                import Wirelet

                @WireFormat
                public struct Point {
                    public var x: Int32
                    public var y: Int32
                    public init(x: Int32, y: Int32) {
                        self.x = x
                        self.y = y
                    }
                }
            """.trimIndent(),
        )

        val result = runner(
            tempDir,
            "generateWireletCodecsMain",
            "generateWireletObservableViewModelsMain",
        ).build()

        assertEquals(
            TaskOutcome.SUCCESS,
            result.task(":generateWireletCodecsMain")?.outcome,
            "wireformat generate task did not run to SUCCESS",
        )
        assertEquals(
            TaskOutcome.SUCCESS,
            result.task(":generateWireletObservableViewModelsMain")?.outcome,
            "observable generate task did not run to SUCCESS",
        )

        val codecFile = tempDir.resolve(
            "build/generated/wirelet/main/kotlin/" +
                "com/example/fixture/codec/PointCodec.kt",
        )
        val viewModelFile = tempDir.resolve(
            "build/generated/wirelet/observable/main/kotlin/" +
                "com/example/fixture/viewmodels/CounterViewModel.kt",
        )
        assertTrue(codecFile.exists(), "PointCodec missing: $codecFile")
        assertTrue(viewModelFile.exists(), "CounterViewModel missing: $viewModelFile")
    }
}
```

- [ ] **Step 2: Run the test, confirm it passes**

Run: `kotlin/gradlew -p kotlin :gradle-plugin:functionalTest --tests ObservableAndCodecsCoexistTest -q`
Expected: PASS. (Both tasks already work in isolation from Task 9 and the existing wireformat suite; this test verifies they don't interfere.)

If `generateWireletObservableViewModelsMain` somehow trips on the `Point.swift` schema (it shouldn't — `Point` is a struct with no `@WireletObservable`), the bug is in the CLI's source enumeration, not the plugin. Verify with `swift run --package-path . emit-wirelet-observable --config … --source … --output …` manually against the fixture sources.

- [ ] **Step 3: Commit**

```bash
git add kotlin/gradle-plugin/src/functionalTest/kotlin/io/github/jiyimeta/wirelet/gradle/ObservableAndCodecsCoexistTest.kt
git commit -m "test(observable): TestKit verifies observable + wireformat coexist with disjoint output"
```

### Task 11: Functional test — incremental rebuild caches

**Files:**
- Modify: existing test (extend the table below) — _no new file_.
- (Optional alternative if a new file is preferred): create `ObservableIncrementalTest.kt` mirroring the existing `IncrementalRebuildTest.kt`.

Confirms that re-running `generateWireletObservableViewModelsMain` with unchanged inputs reports `UP_TO_DATE`, and that a schema edit invalidates the cache. This is the same contract the existing `IncrementalRebuildTest.kt` enforces for wireformat — extend it (or add a sibling test) for the observable task.

- [ ] **Step 1: Read the existing incremental test for pattern reference**

Run: `wc -l kotlin/gradle-plugin/src/functionalTest/kotlin/io/github/jiyimeta/wirelet/gradle/IncrementalRebuildTest.kt`
…and skim it. The pattern is: build once, build a second time, assert second result's task outcome is `UP_TO_DATE`. Then mutate a schema file, build a third time, assert `SUCCESS`.

- [ ] **Step 2: Write `ObservableIncrementalTest.kt`**

Create `kotlin/gradle-plugin/src/functionalTest/kotlin/io/github/jiyimeta/wirelet/gradle/ObservableIncrementalTest.kt` with:

```kotlin
package io.github.jiyimeta.wirelet.gradle

import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals

class ObservableIncrementalTest {
    @Test
    fun upToDateOnSecondRunAndInvalidatesOnSchemaEdit(@TempDir tempDir: File) {
        layoutFixture(
            dir = tempDir,
            extraBuildScript = """
                wirelet {
                    swiftPackagePath.set(file(${'"'}${wireletRepoRoot.absolutePath}${'"'}))
                    observable {
                        register("main") {
                            schemaPaths.from(file("schema"))
                            viewModelPackage.set("com.example.fixture.viewmodels")
                            modelPackage.set("com.example.fixture.model")
                            codecPackage.set("com.example.fixture.codec")
                            libraryName.set("CounterJNI")
                        }
                    }
                }
                tasks.named("compileKotlin") { enabled = false }
            """.trimIndent(),
        )
        writeSchemaFile(
            dir = tempDir,
            relativePath = "schema/CounterVM.swift",
            content = """
                import Observation
                import WireletObservable

                @WireletObservable
                @Observable
                public final class CounterVM {
                    public var count: Int32 = 0
                    public init() {}
                }
            """.trimIndent(),
        )

        val first = runner(tempDir, "generateWireletObservableViewModelsMain").build()
        assertEquals(
            TaskOutcome.SUCCESS,
            first.task(":generateWireletObservableViewModelsMain")?.outcome,
        )

        val second = runner(tempDir, "generateWireletObservableViewModelsMain").build()
        assertEquals(
            TaskOutcome.UP_TO_DATE,
            second.task(":generateWireletObservableViewModelsMain")?.outcome,
            "second run should be UP-TO-DATE with unchanged inputs",
        )

        // Mutate the schema — add a new stored property — and re-run.
        writeSchemaFile(
            dir = tempDir,
            relativePath = "schema/CounterVM.swift",
            content = """
                import Observation
                import WireletObservable

                @WireletObservable
                @Observable
                public final class CounterVM {
                    public var count: Int32 = 0
                    public var label: String = ""
                    public init() {}
                }
            """.trimIndent(),
        )
        val third = runner(tempDir, "generateWireletObservableViewModelsMain").build()
        assertEquals(
            TaskOutcome.SUCCESS,
            third.task(":generateWireletObservableViewModelsMain")?.outcome,
            "schema edit should re-run the task",
        )
    }
}
```

- [ ] **Step 3: Run the test, confirm it passes**

Run: `kotlin/gradlew -p kotlin :gradle-plugin:functionalTest --tests ObservableIncrementalTest -q`
Expected: PASS.

If the second run reports `SUCCESS` instead of `UP_TO_DATE`, something is volatile in the task's inputs — most likely the `cliSourceTree` is including a path that changes between Gradle invocations (e.g. `.build/` artifacts). Re-verify the `include("Sources/**")` filter in `GenerateWireletObservableViewModels.cliSourceTree`.

- [ ] **Step 4: Commit**

```bash
git add kotlin/gradle-plugin/src/functionalTest/kotlin/io/github/jiyimeta/wirelet/gradle/ObservableIncrementalTest.kt
git commit -m "test(observable): TestKit confirms observable task is UP-TO-DATE incremental"
```

---

## Phase 3C: Full-suite verification

### Task 12: Run every Gradle and Swift test in the repo

**Files:** (none — verification only)

- [ ] **Step 1: Full Kotlin Gradle build**

Run: `kotlin/gradlew -p kotlin check`
Expected: `BUILD SUCCESSFUL`. Includes:
- `:runtime:test` (existing 2 suites)
- `:observable-runtime:test` (Task 3's WireletListTest)
- `:gradle-plugin:test` (existing — none currently)
- `:gradle-plugin:functionalTest` (existing 3 + Task 9/10/11's 3 new)
- `:conformance-tests:test` (existing)

If any task fails, treat it as a regression and root-cause before proceeding. The most likely regression target is `:gradle-plugin:functionalTest`'s `IncrementalRebuildTest` if Task 8's plugin wiring accidentally rewired the existing `sources` registration. Diff `WireletPlugin.kt` against the pre-Task-8 version if so.

- [ ] **Step 2: Full Swift test suite**

Run: `swift test`
Expected: previously-passing 88 tests still pass, plus no new failures introduced by the Task 4 emitter retarget.

- [ ] **Step 3: Build observable-runtime as a publishable artifact**

Run: `kotlin/gradlew -p kotlin :observable-runtime:publishToMavenLocal`
Expected: `BUILD SUCCESSFUL` and `~/.m2/repository/io/github/jiyimeta/wirelet-observable-runtime/0.0.0-SNAPSHOT/wirelet-observable-runtime-0.0.0-SNAPSHOT.jar` exists.

Verify:

```bash
ls ~/.m2/repository/io/github/jiyimeta/wirelet-observable-runtime/0.0.0-SNAPSHOT/
```

Expected output includes `wirelet-observable-runtime-0.0.0-SNAPSHOT.jar`, `.pom`, `-sources.jar`.

- [ ] **Step 4: Inspect the published POM**

Run: `cat ~/.m2/repository/io/github/jiyimeta/wirelet-observable-runtime/0.0.0-SNAPSHOT/wirelet-observable-runtime-0.0.0-SNAPSHOT.pom`
Expected: a `<dependencies>` section listing `wirelet-runtime` as a compile-scope dependency (because Task 2's build script uses `api(project(":runtime"))`). No AndroidX, no kotlinx-coroutines.

- [ ] **Step 5: Commit (only if anything was tweaked)**

If Steps 1–4 surfaced small fixes (formatter, missing import, JSON-key drift), commit them under:

```bash
git commit -m "chore(observable): wrap up Phase 3 verification fixes"
```

If nothing needed touching, skip the commit.

---

## Self-review checklist (done)

- **Spec coverage** — Phase 3 covers spec §"Phase 4 — Kotlin runtime + Gradle plugin" (line 518–523) end to end: `kotlin/observable-runtime/` Gradle module with `WireletList` (Task 2/3), `observable` DSL block on the plugin (Tasks 5–8), `generateWireletObservableViewModels` task with disjoint output paths (Task 7/Task 10), Gradle TestKit functional tests (Tasks 9/10/11). The `JObjectGlobalRef` "Runnable wrapper" that the spec mentions at line 361 is **not** needed on the Kotlin side: re-reading the actual emit (`Tests/WireletObservableKotlinEmitterTests/Fixtures/TodoListViewModel.expected.kt`) shows the view-model passes a plain `Runnable { … }` lambda; the global-ref ceremony lives entirely on the Swift `JObject` side (`Sources/WireletObservable/JObject.swift`). Spec wording revisit deferred to Phase 5's README pass.
- **Placeholders** — Task 8 has the only "near-placeholder" — it documents an inline-vs-import choice for `TaskProvider`/`SourceDirectorySet` imports without enforcing one, because either form compiles. Both alternative bodies are shown. Task 4 documents the bootstrap-by-running-and-comparing pattern explicitly so the engineer doesn't have to guess the four-line golden delta.
- **Type consistency** — `WireletObservableSourceSet` properties (Task 5) line up 1:1 with the `GenerateWireletObservableViewModels` task properties (Task 7) and the JSON keys map to `ObservableCodegenConfig` (cross-checked in Task 7 Step 2). The Kotlin `WireletList.decode(bytes, decodePayload)` / `encode(value, encodePayload)` signatures (Task 3) match the emitter retarget (Task 4) — `TodoItemCodec::decodePayload` is a `(BinaryReader) -> TodoItem` reference and `::encodePayload` is `(TodoItem, BinaryWriter) -> Unit`, both directly assignable to the runtime's function-typed parameters. Method names (`decodePayload`, `encodePayload`) appear identically in every existing struct codec produced by the Phase 1 emitter (`Sources/WireletKotlinEmitter/Internal/StructEmitter.swift:106`, `:114`), so no retrofit of the wireformat emitter is required.
- **Scope** — Single subsystem (Kotlin runtime artifact + Gradle plugin DSL). Independent of the Android example (Phase 4) and the publish pipeline (Phase 5). Can be merged on its own — `:observable-runtime` builds, publishes to mavenLocal, and the `observable { … }` DSL works against any consumer that has `swift` on PATH. The example app in Phase 4 will be the first consumer to wire all the pieces together end-to-end against an emulator.

---

## What lands after this plan

This plan ships the Kotlin-side runtime and the Gradle DSL that hosts the Phase 2 emitter. After Phase 3 is on `main`:

1. **Phase 4 plan** — `examples/observable-counter/` end-to-end with Android emulator smoke; extends `examples.yml` CI matrix with an emulator job; adds `conformance-tests/fixtures/observable_burst_v1.txt`.
2. **Phase 5 plan** — README "Observable bridge" section + `v0.2.0` publish wiring `wirelet-observable-runtime` into `publish.yml` alongside `wirelet-runtime`.
