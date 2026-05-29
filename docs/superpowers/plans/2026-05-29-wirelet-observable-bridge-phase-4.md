# Wirelet Observable Bridge — Phase 4: `observable-counter` example + emulator smoke

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land `examples/observable-counter/` — the first end-to-end consumer of the Observable bridge — and extend CI to smoke it on an Android emulator. A Swift `@WireletObservable @Observable final class TodoListVM` cross-compiles to `libObservableCounterJNI.so` for `aarch64-unknown-linux-android`; the bundled `io.github.jiyimeta.wirelet` Gradle plugin regenerates `TodoListVMViewModel.kt` + `TodoItemCodec.kt`; an Android Compose app collects the resulting `StateFlow<…>` properties. An instrumented test asserts a "create → add ×10 → snapshot" burst lands the expected `StateFlow` values. A `kotlin/conformance-tests/fixtures/observable_burst_v1.{bin,json}` fixture locks the wire-level encoding of that same burst sequence. CI gets a new `observable-counter-emulator` job in `examples.yml` that performs the build + emulator smoke from scratch.

**Architecture:**
- `examples/observable-counter/swift/` — single SwiftPM package, one `.library(type: .dynamic)` target (`ObservableCounterJNI`) containing both `TodoItem` (`@WireFormat`) and `TodoListVM` (`@WireletObservable @Observable`). Apple builds compile the macro to nothing observable; the cross-build for `aarch64-unknown-linux-android24` produces `libObservableCounterJNI.so` carrying the macro-emitted `@_cdecl` symbols and the Swift Android runtime dependency chain.
- `examples/observable-counter/android-app/` — Gradle composite root with an `app/` Android module. Applies `io.github.jiyimeta.wirelet` (resolved from `mavenLocal()`); registers one `wirelet.sources` set for the `TodoItem` codec/model and one `wirelet.observable` set for the `TodoListVM` view-model. Compose UI collects `viewModel.items`, `viewModel.totalCount`. Native libs are layered: the project's `libObservableCounterJNI.so` is placed under `app/src/main/jniLibs/arm64-v8a/`, alongside the Swift Android runtime `lib*.so` set copied from the SDK's `swift-resources/.../android/` directory.
- `examples/observable-counter/build.sh` — orchestrator. Publishes `wirelet-runtime`, `wirelet-observable-runtime`, `wirelet-gradle-plugin` to `mavenLocal` with a pinned local version, cross-compiles the Swift package, stages all required `.so` files into `jniLibs`, then `./gradlew assembleDebug`.
- `examples/observable-counter/run-emulator.sh` — assumes an emulator is already booted; installs the debug APK, runs the instrumented test, prints PASS/FAIL.
- `examples/observable-counter/verify.sh` — combines the two for CI / local one-shot: build the bits, then run the instrumented suite against the already-running emulator the workflow has provisioned.
- `.github/workflows/examples.yml` gains an `observable-counter-emulator` job, ubuntu-latest, using `reactivecircus/android-emulator-runner@v2` to provision an emulator, with steps to install Swift 6.3.2 + the matching Android Swift SDK before running `verify.sh`.
- `kotlin/conformance-tests/fixtures/observable_burst_v1.bin` — a single TLV stream that encodes the canonical `add ×10` burst's final `items: [TodoItem]` array using the same `WireFormat` codec the runtime emits. The matched `.json` describes the expected list element-for-element. `FixtureRunner.kt` gains a `@Test observableBurst()` that decodes the `.bin` and round-trips it via `WireletList`.

**Tech Stack:** Swift 6.3.2 (host + Android SDK), Swift Android SDK `swift-6.3.2-RELEASE_android` (target triple `aarch64-unknown-linux-android24`, NDK r26.1+ bundled in the SDK artifactbundle), Android Gradle Plugin 8.x, Kotlin 2.x, Compose Compiler / BOM, Android API 34 system image (Google APIs, ARM64 emulator on CI via KVM-enabled Linux runners), `androidx.lifecycle.viewmodel-compose`, `kotlinx-coroutines-android`, `androidx.test:runner` / `androidx.test.ext:junit` for instrumented tests, `reactivecircus/android-emulator-runner@v2` for the CI emulator.

---

## File Structure

**Create:**
- `examples/observable-counter/README.md` — quickstart.
- `examples/observable-counter/swift/Package.swift` — single SwiftPM package (Phase 4A).
- `examples/observable-counter/swift/Sources/ObservableCounterJNI/TodoItem.swift` — `@WireFormat` struct.
- `examples/observable-counter/swift/Sources/ObservableCounterJNI/TodoListVM.swift` — `@WireletObservable @Observable` class.
- `examples/observable-counter/android-app/settings.gradle.kts` — Gradle settings.
- `examples/observable-counter/android-app/build.gradle.kts` — root build script.
- `examples/observable-counter/android-app/gradle.properties` — JVM args + AndroidX.
- `examples/observable-counter/android-app/gradlew`, `gradlew.bat`, `gradle/wrapper/gradle-wrapper.jar`, `gradle/wrapper/gradle-wrapper.properties` — Gradle wrapper.
- `examples/observable-counter/android-app/app/build.gradle.kts` — Android app module.
- `examples/observable-counter/android-app/app/src/main/AndroidManifest.xml`.
- `examples/observable-counter/android-app/app/src/main/kotlin/io/github/jiyimeta/observablecounter/MainActivity.kt`.
- `examples/observable-counter/android-app/app/src/main/kotlin/io/github/jiyimeta/observablecounter/TodoScreen.kt`.
- `examples/observable-counter/android-app/app/src/main/res/values/strings.xml`.
- `examples/observable-counter/android-app/app/src/main/res/values/themes.xml`.
- `examples/observable-counter/android-app/app/src/androidTest/kotlin/io/github/jiyimeta/observablecounter/TodoBurstInstrumentedTest.kt`.
- `examples/observable-counter/build.sh` — full build orchestrator.
- `examples/observable-counter/run-emulator.sh` — install + instrumented test.
- `examples/observable-counter/verify.sh` — CI / local one-shot.
- `examples/observable-counter/.gitignore`.
- `kotlin/conformance-tests/fixtures/observable_burst_v1.bin`.
- `kotlin/conformance-tests/fixtures/observable_burst_v1.json`.
- `Tests/ConformanceTests/ObservableBurstFixtureGenerator.swift` — disabled-by-default fixture writer mirroring the existing pattern.

**Modify:**
- `kotlin/conformance-tests/src/test/kotlin/io/github/jiyimeta/wirelet/conformance/FixtureRunner.kt` — add `observableBurst()` decode test.
- `.github/workflows/examples.yml` — add `observable-counter-emulator` job.
- `README.md` — add the example to the table of examples.
- `docs/getting-started-kotlin.md` — link to the example from the "Observable" section (new short section).
- `docs/getting-started-swift.md` — mention `@WireletObservable` from a sentence + link to the example.

**Out of scope (Phase 5):**
- README "Observable bridge" feature section (long form) — Phase 5 ships this with v0.2.0.
- Publishing `wirelet-observable-runtime` to GitHub Packages — Phase 5 wires into `publish.yml`.
- Cleaning up the `0.0.1-local` version sentinel — Phase 5 swaps for the released version.

---

## Phase 4A: Swift package scaffolding

### Task 1: Scaffold the example directory + README skeleton

**Files:**
- Create: `examples/observable-counter/README.md`
- Create: `examples/observable-counter/.gitignore`

- [ ] **Step 1: Write `README.md`**

```markdown
# `observable-counter` — end-to-end Wirelet Observable bridge demo

Mirrors `cross-roundtrip`'s shape, but exercises the Observable side of the
bridge end to end: a Swift `@WireletObservable @Observable` class crosses the
JNI boundary as an Android `ViewModel` whose `StateFlow` properties are
collected by Compose.

```
shared between Swift impl + Kotlin codegen
├── swift/                       SwiftPM package
│   ├── Package.swift            type: .dynamic → libObservableCounterJNI.so
│   └── Sources/ObservableCounterJNI/
│       ├── TodoItem.swift       @WireFormat struct
│       └── TodoListVM.swift     @WireletObservable @Observable class
├── android-app/                 standalone Gradle project
│   └── app/                     :app — Android module
└── build.sh                     publishToMavenLocal → cross-compile → assembleDebug
```

## One-shot verification

The script below boots no emulator; it assumes one is already running
(`emulator -avd <name>` in another shell). To run end to end from cold:

```bash
./examples/observable-counter/verify.sh
```

See [the Phase 4 implementation plan](../../docs/superpowers/plans/2026-05-29-wirelet-observable-bridge-phase-4.md)
for the design rationale.
```

- [ ] **Step 2: Write `.gitignore`**

```
android-app/.gradle/
android-app/build/
android-app/app/build/
android-app/local.properties
swift/.build/
swift/.swiftpm/
*.so
!**/jniLibs/**/*.so
```

The negation re-includes files dropped into `jniLibs/` by `build.sh`. (In
this plan we *do not* commit `.so` files — they're build artifacts staged at
build time. The negation is defensive in case a future change commits one.)

Update: do not commit any built `.so`. Replace the negation rule with an
explicit `app/src/main/jniLibs/` ignore:

```
android-app/.gradle/
android-app/build/
android-app/app/build/
android-app/local.properties
android-app/app/src/main/jniLibs/
swift/.build/
swift/.swiftpm/
```

- [ ] **Step 3: Commit**

```bash
git add examples/observable-counter/README.md examples/observable-counter/.gitignore
git commit -m "docs(observable-counter): scaffold example directory + README"
```

### Task 2: Swift package — `TodoItem` (`@WireFormat`)

**Files:**
- Create: `examples/observable-counter/swift/Package.swift`
- Create: `examples/observable-counter/swift/Sources/ObservableCounterJNI/TodoItem.swift`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ObservableCounterJNI",
    products: [
        // `type: .dynamic` is required so the SwiftPM cross-build for
        // aarch64-unknown-linux-android24 produces libObservableCounterJNI.so
        // (vs an .a static archive that Android cannot dlopen).
        .library(
            name: "ObservableCounterJNI",
            type: .dynamic,
            targets: ["ObservableCounterJNI"]
        ),
    ],
    dependencies: [
        // Relative path from examples/observable-counter/swift/ up to repo root.
        .package(path: "../../.."),
    ],
    targets: [
        .target(
            name: "ObservableCounterJNI",
            dependencies: [
                .product(name: "Wirelet", package: "swift-wirelet"),
                .product(name: "WireletObservable", package: "swift-wirelet"),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Write `TodoItem.swift`**

```swift
import Wirelet

/// Single to-do row. Bridged across the JNI boundary as a `WireFormat` TLV
/// payload; the macro-emitted `TodoItemCodec` on the Kotlin side decodes
/// the same bytes back into a data class. Fields ordered to match the
/// schema in `docs/superpowers/specs/2026-05-29-wirelet-observable-bridge-design.md`.
@WireFormat
public struct TodoItem: Equatable, Sendable {
    public var id: Int32
    public var title: String
    public var done: Bool

    public init(id: Int32, title: String, done: Bool) {
        self.id = id
        self.title = title
        self.done = done
    }
}
```

- [ ] **Step 3: Verify the package resolves**

Run: `swift package --package-path examples/observable-counter/swift describe --type json | head -3`
Expected: JSON banner lines, no error.

- [ ] **Step 4: Commit**

```bash
git add examples/observable-counter/swift/
git commit -m "feat(observable-counter): add SwiftPM package + TodoItem WireFormat struct"
```

### Task 3: Swift package — `TodoListVM` (`@WireletObservable`)

**Files:**
- Create: `examples/observable-counter/swift/Sources/ObservableCounterJNI/TodoListVM.swift`

- [ ] **Step 1: Write `TodoListVM.swift`**

```swift
import Observation
import Wirelet
import WireletObservable

/// View-model exposed to the Android app as `TodoListVMViewModel`.
///
/// - `items` mirrors a `StateFlow<List<TodoItem>>` on Kotlin.
/// - `totalCount` mirrors a `StateFlow<Int>`.
/// - `filter` mirrors a `StateFlow<String>`.
/// - `add(_:)` and `clear()` are bridged as `external fun nativeAdd(...)`
///   / `nativeClear(...)` because they carry `@WireletExpose`.
///
/// Apple builds compile the macro to a no-op extension; only the Android
/// cross-build emits the `@_cdecl` JNI bridges.
@WireletObservable
@Observable
public final class TodoListVM {
    public var items: [TodoItem] = []
    public var filter: String = ""
    public var totalCount: Int32 = 0

    public init() {}

    @WireletExpose
    public func add(_ item: TodoItem) {
        items.append(item)
        totalCount += 1
    }

    @WireletExpose
    public func clear() {
        items.removeAll()
        totalCount = 0
    }
}
```

- [ ] **Step 2: Verify the package builds for the host**

Run: `swift build --package-path examples/observable-counter/swift`
Expected: builds cleanly. The macro emits the `@_cdecl`-bearing extension
under `#if os(Android)`; on macOS the extension body is empty.

- [ ] **Step 3: Commit**

```bash
git add examples/observable-counter/swift/Sources/ObservableCounterJNI/TodoListVM.swift
git commit -m "feat(observable-counter): add TodoListVM @WireletObservable class"
```

### Task 4: Cross-compile sanity check — produce `libObservableCounterJNI.so`

**Files:**
- (No files; verification only.)

This task validates that the Swift Android SDK is wired up correctly on
the host and that the dynamic library product produces a usable `.so`. It
will be re-run inside `build.sh` later; for now we just confirm the
toolchain works at the command line.

- [ ] **Step 1: Confirm the SDK is installed**

Run: `swift sdk list`
Expected: output contains `swift-6.3.2-RELEASE_android` (or a newer matching SDK).
If absent, install per <https://www.swift.org/install/> "Cross-compilation
for Android" — the bundle ships an artifactbundle that registers all three
Android ABIs against the matching host Swift toolchain.

- [ ] **Step 2: Cross-compile**

Run:
```bash
swift build \
  --package-path examples/observable-counter/swift \
  --swift-sdk aarch64-unknown-linux-android24 \
  -c release
```
Expected: completes without errors. Output:
`.build/aarch64-unknown-linux-android24/release/libObservableCounterJNI.so`.

If the build fails citing a missing `-aapt`, `-clang`, or
`libc++_shared.so`, the SDK is installed but the NDK sysroot inside the
artifactbundle was not unpacked correctly; re-run `swift sdk install`
against the artifactbundle URL.

- [ ] **Step 3: Confirm the `@_cdecl` symbols are exported**

Run:
```bash
nm -D --defined-only \
  examples/observable-counter/swift/.build/aarch64-unknown-linux-android24/release/libObservableCounterJNI.so \
  | grep WireletObservable_TodoListVM_ \
  | sort
```
Expected: at minimum the following are present:
```
WireletObservable_TodoListVM_add_invoke
WireletObservable_TodoListVM_clear_invoke
WireletObservable_TodoListVM_filter_set
WireletObservable_TodoListVM_filter_track
WireletObservable_TodoListVM_items_set
WireletObservable_TodoListVM_items_track
WireletObservable_TodoListVM_new
WireletObservable_TodoListVM_release
WireletObservable_TodoListVM_totalCount_set
WireletObservable_TodoListVM_totalCount_track
```
If any symbol is missing, the macro expansion did not include it. Cross-
check the macro fixture `Tests/WireletObservableMacrosTests/Fixtures/`
for the expected expansion, and ensure the property's type is one of the
supported kinds. Fix the macro before continuing.

- [ ] **Step 4: No commit** — verification only.

---

## Phase 4B: Android Gradle skeleton + Wirelet plugin wiring

### Task 5: Android Gradle skeleton — settings, wrapper, root build

**Files:**
- Create: `examples/observable-counter/android-app/settings.gradle.kts`
- Create: `examples/observable-counter/android-app/build.gradle.kts`
- Create: `examples/observable-counter/android-app/gradle.properties`
- Create: `examples/observable-counter/android-app/gradle/wrapper/gradle-wrapper.properties`
- Create: Gradle wrapper script files (see Step 4)

The wrapper version and AGP version must align: AGP 8.7 needs Gradle 8.9+
according to the AGP release notes. Pin both.

- [ ] **Step 1: Write `settings.gradle.kts`**

```kotlin
pluginManagement {
    repositories {
        gradlePluginPortal()
        google()
        mavenCentral()
        mavenLocal()  // resolves io.github.jiyimeta.wirelet from publishToMavenLocal
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        mavenLocal()  // resolves wirelet-runtime + wirelet-observable-runtime
    }
}

rootProject.name = "observable-counter"
include(":app")
```

- [ ] **Step 2: Write the root `build.gradle.kts`**

```kotlin
plugins {
    id("com.android.application") version "8.7.0" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21" apply false
    id("io.github.jiyimeta.wirelet") version "0.0.1-local" apply false
}
```

- [ ] **Step 3: Write `gradle.properties`**

```
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
```

- [ ] **Step 4: Stamp the Gradle wrapper**

There is no shipped Gradle wrapper inside the worktree's other gradle
projects we can copy from directly — they use the repo-root
`kotlin/gradlew` instead. Generate a fresh wrapper from the host Gradle
install:

```bash
( cd examples/observable-counter/android-app \
  && gradle wrapper --gradle-version 8.10 )
```

Then commit the four files Gradle wrote (`gradlew`, `gradlew.bat`,
`gradle/wrapper/gradle-wrapper.jar`, `gradle/wrapper/gradle-wrapper.properties`).
Verify by running:

```bash
( cd examples/observable-counter/android-app && ./gradlew --version )
```

Expected: prints `Gradle 8.10` and the Kotlin / JVM versions.

- [ ] **Step 5: Commit**

```bash
git add examples/observable-counter/android-app/settings.gradle.kts \
  examples/observable-counter/android-app/build.gradle.kts \
  examples/observable-counter/android-app/gradle.properties \
  examples/observable-counter/android-app/gradlew \
  examples/observable-counter/android-app/gradlew.bat \
  examples/observable-counter/android-app/gradle/wrapper/gradle-wrapper.jar \
  examples/observable-counter/android-app/gradle/wrapper/gradle-wrapper.properties
git commit -m "feat(observable-counter): scaffold Android Gradle project + wrapper"
```

### Task 6: `:app` Android module — build script

**Files:**
- Create: `examples/observable-counter/android-app/app/build.gradle.kts`

The build script needs three things layered:
1. Android Compose application config.
2. Wirelet plugin DSL: `sources` set generates `TodoItem` / `TodoItemCodec`; `observable` set generates `TodoListVMViewModel`.
3. Dependencies on `wirelet-runtime` + `wirelet-observable-runtime` from `mavenLocal`.

- [ ] **Step 1: Write `app/build.gradle.kts`**

```kotlin
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("io.github.jiyimeta.wirelet")
}

android {
    namespace = "io.github.jiyimeta.observablecounter"
    compileSdk = 34

    defaultConfig {
        applicationId = "io.github.jiyimeta.observablecounter"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk {
            // Match the Swift cross-compile target. arm64-v8a only, no x86.
            abiFilters += "arm64-v8a"
        }
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    sourceSets["main"].kotlin.srcDirs("src/main/kotlin")
    sourceSets["androidTest"].kotlin.srcDirs("src/androidTest/kotlin")
}

wirelet {
    // Repo root is four levels up:
    //   examples/observable-counter/android-app/app/  →  ../../../..
    swiftPackagePath.set(file("../../../.."))

    sources {
        register("main") {
            schemaPaths.from(file("../../swift/Sources/ObservableCounterJNI"))
            packageName.set("io.github.jiyimeta.observablecounter")
            // emit-wirelet-kotlin scans `@WireFormat` types; TodoItem matches.
        }
    }

    observable {
        register("main") {
            schemaPaths.from(file("../../swift/Sources/ObservableCounterJNI"))
            viewModelPackage.set("io.github.jiyimeta.observablecounter.generated")
            modelPackage.set("io.github.jiyimeta.observablecounter")
            codecPackage.set("io.github.jiyimeta.observablecounter")
            libraryName.set("ObservableCounterJNI")
        }
    }
}

dependencies {
    implementation("io.github.jiyimeta:wirelet-runtime:0.0.1-local")
    implementation("io.github.jiyimeta:wirelet-observable-runtime:0.0.1-local")

    // Compose + lifecycle. Versions intentionally inlined (no version
    // catalogue) to keep the example readable as a self-contained build.
    val composeBom = platform("androidx.compose:compose-bom:2024.10.00")
    implementation(composeBom)
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    androidTestImplementation("androidx.test:core:1.6.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:rules:1.6.1")
}
```

- [ ] **Step 2: Sanity-evaluate the script**

Run:
```bash
( cd examples/observable-counter/android-app \
  && ./gradlew :app:tasks --group=verification 2>&1 | head -20 )
```
Expected: prints `connectedCheck`, `connectedDebugAndroidTest`, etc. tasks
without configuration-time errors. (We are not running the build yet;
this is purely a script-parses check.)

If Gradle complains that `io.github.jiyimeta.wirelet` is missing, that's
expected — Task 8 publishes it to `mavenLocal` first. For this sanity
pass, comment out the plugin line temporarily; uncomment before commit.

- [ ] **Step 3: Commit**

```bash
git add examples/observable-counter/android-app/app/build.gradle.kts
git commit -m "feat(observable-counter): add :app Android module build script"
```

### Task 7: `:app` source skeleton — Manifest, theme, strings

**Files:**
- Create: `examples/observable-counter/android-app/app/src/main/AndroidManifest.xml`
- Create: `examples/observable-counter/android-app/app/src/main/res/values/strings.xml`
- Create: `examples/observable-counter/android-app/app/src/main/res/values/themes.xml`

- [ ] **Step 1: Write `AndroidManifest.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <application
        android:label="@string/app_name"
        android:theme="@style/Theme.ObservableCounter"
        android:allowBackup="false"
        android:supportsRtl="true">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
```

- [ ] **Step 2: Write `res/values/strings.xml`**

```xml
<resources>
    <string name="app_name">Observable Counter</string>
</resources>
```

- [ ] **Step 3: Write `res/values/themes.xml`**

```xml
<resources>
    <style name="Theme.ObservableCounter" parent="android:Theme.Material.Light.NoActionBar" />
</resources>
```

- [ ] **Step 4: Commit**

```bash
git add examples/observable-counter/android-app/app/src/main/AndroidManifest.xml \
  examples/observable-counter/android-app/app/src/main/res/
git commit -m "feat(observable-counter): add :app manifest + theme + strings"
```

### Task 8: First publish — `wirelet-runtime` + `wirelet-observable-runtime` + plugin to `mavenLocal`

**Files:**
- (No files; build orchestration verification.)

The Android app's `wirelet { ... }` block fails to resolve until the
plugin and runtime artifacts are in `mavenLocal`. Land a clean local
publish before any Android-side work that touches the wirelet plugin.

- [ ] **Step 1: Publish from the repo's `kotlin/` Gradle root**

Run:
```bash
kotlin/gradlew \
  -PwireletVersion=0.0.1-local \
  :runtime:publishToMavenLocal \
  :observable-runtime:publishToMavenLocal \
  :gradle-plugin:publishToMavenLocal
```
Expected: `BUILD SUCCESSFUL`. Verify artifacts on disk:
```bash
ls ~/.m2/repository/io/github/jiyimeta/wirelet-runtime/0.0.1-local/
ls ~/.m2/repository/io/github/jiyimeta/wirelet-observable-runtime/0.0.1-local/
ls ~/.m2/repository/io/github/jiyimeta/wirelet-gradle-plugin/0.0.1-local/
```
Each directory must contain a `.jar` (or `.aar` for runtime — runtime is
plain JVM, so `.jar`) plus `.pom` and `.module`.

- [ ] **Step 2: Re-evaluate the `:app` script with the plugin line restored**

Run:
```bash
( cd examples/observable-counter/android-app \
  && ./gradlew :app:tasks --group=verification 2>&1 | head -20 )
```
Expected: configures without "plugin not found" errors.

- [ ] **Step 3: Verify the Wirelet observable task appears**

Run:
```bash
( cd examples/observable-counter/android-app \
  && ./gradlew :app:tasks --all 2>&1 \
  | grep generateWireletObservable )
```
Expected: a line like `generateWireletObservableViewModelsMain`.

- [ ] **Step 4: No commit** — verification only.

### Task 9: Generate the `<Name>ViewModel.kt` from schema (smoke)

**Files:**
- (No files; runs the existing generate task in isolation.)

- [ ] **Step 1: Run the observable generate task**

Run:
```bash
( cd examples/observable-counter/android-app \
  && ./gradlew :app:generateWireletObservableViewModelsMain )
```
Expected: `BUILD SUCCESSFUL`. Confirm the generated file exists:
```bash
test -f examples/observable-counter/android-app/app/build/generated/wirelet/observable/main/kotlin/io/github/jiyimeta/observablecounter/generated/TodoListVMViewModel.kt
```

- [ ] **Step 2: Inspect the generated file**

Run:
```bash
sed -n '1,30p' examples/observable-counter/android-app/app/build/generated/wirelet/observable/main/kotlin/io/github/jiyimeta/observablecounter/generated/TodoListVMViewModel.kt
```
Expected: includes `class TodoListVMViewModel internal constructor`,
`val items: StateFlow<List<TodoItem>>`, and `System.loadLibrary("ObservableCounterJNI")`.

- [ ] **Step 3: Run the wireformat sources task**

Run:
```bash
( cd examples/observable-counter/android-app \
  && ./gradlew :app:generateWireletCodecsMain )
```
Expected: generates `TodoItem.kt` (model) + `TodoItemCodec.kt` (codec)
under `build/generated/wirelet/<sources-name>/...`. Inspect:
```bash
find examples/observable-counter/android-app/app/build/generated/wirelet -name '*.kt'
```
Both files must be present; the generated ViewModel must `import` them
from the package configured on the observable source set.

- [ ] **Step 4: No commit** — verification only.

---

## Phase 4C: Compose UI + instrumented smoke

### Task 10: `MainActivity` + Compose UI

**Files:**
- Create: `examples/observable-counter/android-app/app/src/main/kotlin/io/github/jiyimeta/observablecounter/MainActivity.kt`
- Create: `examples/observable-counter/android-app/app/src/main/kotlin/io/github/jiyimeta/observablecounter/TodoScreen.kt`

The UI is intentionally minimal: one button that calls
`viewModel.add(TodoItem(...))`, one button that clears, a list rendering
`items`, and a header showing `totalCount`. It exercises every code
path the bridge needs to bridge.

- [ ] **Step 1: Write `MainActivity.kt`**

```kotlin
package io.github.jiyimeta.observablecounter

import android.app.Activity
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import io.github.jiyimeta.observablecounter.generated.TodoListVMViewModel

class MainActivity : ComponentActivity() {
    private val viewModel: TodoListVMViewModel by viewModels { ViewModelFactory }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { TodoScreen(viewModel) }
    }
}

private object ViewModelFactory : ViewModelProvider.Factory {
    @Suppress("UNCHECKED_CAST")
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(TodoListVMViewModel::class.java)) {
            return TodoListVMViewModel.create() as T
        }
        throw IllegalArgumentException("Unknown ViewModel class: $modelClass")
    }
}
```

`TodoListVMViewModel.create()` is the static factory the Phase 3 emitter
generates inside the companion object. It calls `nativeNew()` and wraps
the returned `Long`.

- [ ] **Step 2: Write `TodoScreen.kt`**

```kotlin
package io.github.jiyimeta.observablecounter

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.github.jiyimeta.observablecounter.generated.TodoListVMViewModel

@Composable
fun TodoScreen(viewModel: TodoListVMViewModel) {
    val items by viewModel.items.collectAsStateWithLifecycle()
    val totalCount by viewModel.totalCount.collectAsStateWithLifecycle()
    Surface {
        Column(modifier = Modifier.padding(16.dp).fillMaxSize()) {
            Text("total=$totalCount", modifier = Modifier.testTag("total"))
            Button(
                onClick = {
                    val next = totalCount + 1
                    viewModel.add(TodoItem(id = next, title = "task #$next", done = false))
                },
                modifier = Modifier.testTag("add"),
            ) { Text("Add") }
            Button(onClick = viewModel::clear, modifier = Modifier.testTag("clear")) {
                Text("Clear")
            }
            Spacer(Modifier.height(8.dp))
            LazyColumn(modifier = Modifier.testTag("list")) {
                items(items) { item ->
                    Row(modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                        Checkbox(checked = item.done, onCheckedChange = null)
                        Text(item.title, modifier = Modifier.padding(start = 8.dp))
                    }
                }
            }
        }
    }
}
```

The `testTag(...)` annotations are how the instrumented test finds nodes
deterministically (no string matching against rendered text).

- [ ] **Step 3: Commit**

```bash
git add examples/observable-counter/android-app/app/src/main/kotlin/
git commit -m "feat(observable-counter): add MainActivity + Compose TodoScreen"
```

### Task 11: Stage the `.so` set into `jniLibs/`

**Files:**
- (No files committed; build-time staging.)

For the APK to be runnable in an emulator, four artifact groups land
under `app/src/main/jniLibs/arm64-v8a/`:

1. `libObservableCounterJNI.so` — the project's own dynamic library
   (produced by Task 4).
2. The Swift Android runtime `lib*.so` set from the artifactbundle's
   `swift-resources/usr/lib/swift-aarch64/android/` directory. These are
   loaded transitively when `System.loadLibrary("ObservableCounterJNI")`
   runs.
3. `libc++_shared.so` from the NDK sysroot bundled in the artifactbundle.
4. The artifactbundle's `swift-android/ndk-sysroot/usr/lib/aarch64-linux-android/24/`
   stub for `liblog.so`, `libdl.so`, etc. — *not* copied; these are
   provided by Android itself and the dynamic linker resolves them at
   load time.

The set of (2) is non-obvious. Discover it on the running host first.

- [ ] **Step 1: List the Swift Android runtime `.so` set**

Run:
```bash
SDK_LIB="$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3.2-RELEASE_android.artifactbundle/swift-android/swift-resources/usr/lib/swift-aarch64/android"
ls "$SDK_LIB" | grep '\.so$' | sort
```
Expected: a list containing `libswiftCore.so`, `libswiftAndroid.so`,
`libswift_Concurrency.so`, `libswift_StringProcessing.so`,
`libFoundation.so`, `libFoundationEssentials.so`,
`libFoundationInternationalization.so`, `libBlocksRuntime.so`,
`libdispatch.so`, `lib_FoundationICU.so`, etc.

- [ ] **Step 2: Locate `libc++_shared.so` in the NDK sysroot**

Run:
```bash
find "$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3.2-RELEASE_android.artifactbundle/swift-android/ndk-sysroot" \
  -name libc++_shared.so 2>/dev/null
```
Expected: one or more paths under the sysroot's aarch64 toolchain lib
directory. Pick the one under `aarch64-linux-android/`.

- [ ] **Step 3: Stage them by hand for the first build**

Run:
```bash
DEST="examples/observable-counter/android-app/app/src/main/jniLibs/arm64-v8a"
mkdir -p "$DEST"
cp examples/observable-counter/swift/.build/aarch64-unknown-linux-android24/release/libObservableCounterJNI.so "$DEST/"
cp "$SDK_LIB"/lib*.so "$DEST/"
LIBCXX_SRC="$(find "$HOME/Library/org.swift.swiftpm/swift-sdks/swift-6.3.2-RELEASE_android.artifactbundle/swift-android/ndk-sysroot" -name libc++_shared.so | grep aarch64 | head -1)"
cp "$LIBCXX_SRC" "$DEST/"
ls "$DEST"
```
Expected: a directory listing that includes `libObservableCounterJNI.so`,
`libswiftCore.so`, `libFoundation.so`, `libc++_shared.so`, and the
rest of the runtime set.

- [ ] **Step 4: First `assembleDebug`**

Run:
```bash
( cd examples/observable-counter/android-app && ./gradlew :app:assembleDebug )
```
Expected: `BUILD SUCCESSFUL`. The APK is at
`app/build/outputs/apk/debug/app-debug.apk`. Confirm the JNI libs are
packaged:
```bash
unzip -l examples/observable-counter/android-app/app/build/outputs/apk/debug/app-debug.apk \
  | grep arm64-v8a/libObservableCounterJNI.so
```

- [ ] **Step 5: No commit** — staging is reproduced by `build.sh` in Task 14.

### Task 12: Instrumented test — burst sequence

**Files:**
- Create: `examples/observable-counter/android-app/app/src/androidTest/kotlin/io/github/jiyimeta/observablecounter/TodoBurstInstrumentedTest.kt`

The test directly drives the ViewModel (no UI interaction) and waits on
the `StateFlow` reaching the expected snapshot. Driving via the VM is
faster and avoids Compose recomposition timing flake on the emulator.

- [ ] **Step 1: Write `TodoBurstInstrumentedTest.kt`**

```kotlin
package io.github.jiyimeta.observablecounter

import androidx.test.ext.junit.runners.AndroidJUnit4
import io.github.jiyimeta.observablecounter.generated.TodoListVMViewModel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.flow.first
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TodoBurstInstrumentedTest {

    /**
     * Drives 10 sequential `add(...)` calls against a single VM and
     * asserts the final StateFlow snapshot reflects all 10 mutations.
     *
     * This is the Phase 4 emulator smoke: if the JNI bridge round-trip
     * is broken, `items` either hangs, comes back empty, or has fewer
     * elements than mutations.
     */
    @Test
    fun addBurstReachesExpectedSnapshot() = runBlocking {
        val vm = TodoListVMViewModel.create()
        repeat(10) { i ->
            vm.add(TodoItem(id = i + 1, title = "task #${i + 1}", done = false))
        }
        // wait until items reflects all 10 entries
        val finalItems = vm.items
            .first { snapshot -> snapshot.size == 10 }
        assertEquals(10, finalItems.size)
        finalItems.forEachIndexed { idx, item ->
            assertEquals((idx + 1).toInt(), item.id)
            assertEquals("task #${idx + 1}", item.title)
            assertEquals(false, item.done)
        }
        val finalTotal = vm.totalCount.first { it == 10 }
        assertEquals(10, finalTotal)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add examples/observable-counter/android-app/app/src/androidTest/kotlin/
git commit -m "test(observable-counter): instrumented burst test asserts StateFlow shape"
```

### Task 13: Local emulator smoke — manual end-to-end

**Files:**
- (No files; verification only.)

- [ ] **Step 1: Boot an emulator**

Run (in a separate terminal, not via the agent):
```bash
$ANDROID_HOME/emulator/emulator -avd <name-of-arm64-v8a-API-34-AVD>
```
If no suitable AVD exists, create one in Android Studio's AVD Manager
using Android 14.0 (API 34), arm64-v8a (ARM 64) image. Wait for the
home screen to render.

- [ ] **Step 2: Run the instrumented test**

Run:
```bash
( cd examples/observable-counter/android-app \
  && ./gradlew :app:connectedDebugAndroidTest )
```
Expected: `BUILD SUCCESSFUL`, with a report under
`app/build/reports/androidTests/connected/`. The `TodoBurstInstrumentedTest.addBurstReachesExpectedSnapshot`
test must pass.

Common failure modes:
- `UnsatisfiedLinkError: dlopen ... libObservableCounterJNI.so`: a
  required Swift runtime `.so` is missing from `jniLibs/`. Re-run the
  Task 11 staging script and double-check the listing.
- `NoSuchMethodError: WireletObservable_TodoListVM_add_invoke`: macro
  expansion is incomplete. Re-run Task 4 Step 3.
- Test hangs on `vm.items.first { snapshot -> snapshot.size == 10 }`:
  the re-arm loop is broken. Inspect `logcat | grep WireletObservable`
  for `JNI` errors.

- [ ] **Step 3: No commit** — verification only.

---

## Phase 4D: Driver scripts

### Task 14: `build.sh` — full build orchestrator

**Files:**
- Create: `examples/observable-counter/build.sh`

- [ ] **Step 1: Write `build.sh`**

```bash
#!/usr/bin/env bash
#
# Build the observable-counter example end-to-end.
#
# 1. Publish wirelet-runtime + wirelet-observable-runtime + plugin to mavenLocal.
# 2. Cross-compile libObservableCounterJNI.so for aarch64-unknown-linux-android24.
# 3. Stage the .so + Swift Android runtime + libc++_shared.so into jniLibs.
# 4. assembleDebug.
#
# Inputs: none. Outputs: APK at app/build/outputs/apk/debug/app-debug.apk.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SDK_ID="swift-6.3.2-RELEASE_android"
SDK_LIB="$HOME/Library/org.swift.swiftpm/swift-sdks/${SDK_ID}.artifactbundle/swift-android/swift-resources/usr/lib/swift-aarch64/android"
SDK_NDK="$HOME/Library/org.swift.swiftpm/swift-sdks/${SDK_ID}.artifactbundle/swift-android/ndk-sysroot"
ANDROID_TRIPLE="aarch64-unknown-linux-android24"
SWIFT_PKG="$HERE/swift"
ANDROID_APP="$HERE/android-app"
JNI_DEST="$ANDROID_APP/app/src/main/jniLibs/arm64-v8a"

echo "=== publishToMavenLocal ==="
"$ROOT/kotlin/gradlew" \
  -p "$ROOT/kotlin" \
  -PwireletVersion=0.0.1-local \
  :runtime:publishToMavenLocal \
  :observable-runtime:publishToMavenLocal \
  :gradle-plugin:publishToMavenLocal

echo "=== cross-compile Swift -> $ANDROID_TRIPLE ==="
swift build \
  --package-path "$SWIFT_PKG" \
  --swift-sdk "$ANDROID_TRIPLE" \
  -c release

echo "=== stage jniLibs ==="
rm -rf "$JNI_DEST"
mkdir -p "$JNI_DEST"
cp "$SWIFT_PKG/.build/$ANDROID_TRIPLE/release/libObservableCounterJNI.so" "$JNI_DEST/"
cp "$SDK_LIB"/lib*.so "$JNI_DEST/"
LIBCXX="$(find "$SDK_NDK" -name libc++_shared.so | grep aarch64 | head -1)"
if [ -z "$LIBCXX" ]; then
  echo "FATAL: libc++_shared.so not found under $SDK_NDK" >&2
  exit 1
fi
cp "$LIBCXX" "$JNI_DEST/"
echo "Staged $(ls "$JNI_DEST" | wc -l | tr -d ' ') .so files."

echo "=== assembleDebug ==="
( cd "$ANDROID_APP" && ./gradlew :app:assembleDebug )

echo
echo "SUCCESS. APK at:"
echo "  $ANDROID_APP/app/build/outputs/apk/debug/app-debug.apk"
```

- [ ] **Step 2: Mark executable + smoke**

Run:
```bash
chmod +x examples/observable-counter/build.sh
./examples/observable-counter/build.sh
```
Expected: ends with `SUCCESS. APK at: …`. The script is hermetic — it
clears `jniLibs/` and re-stages everything from scratch.

- [ ] **Step 3: Commit**

```bash
git add examples/observable-counter/build.sh
git commit -m "feat(observable-counter): add build.sh full-build orchestrator"
```

### Task 15: `run-emulator.sh` + `verify.sh`

**Files:**
- Create: `examples/observable-counter/run-emulator.sh`
- Create: `examples/observable-counter/verify.sh`

- [ ] **Step 1: Write `run-emulator.sh`**

```bash
#!/usr/bin/env bash
#
# Install the debug APK against an already-running emulator + run the
# instrumented burst test. Caller is responsible for booting the
# emulator first (`emulator -avd <name>` or the CI matrix runner).

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_APP="$HERE/android-app"

echo "=== checking for connected device ==="
"$ANDROID_HOME/platform-tools/adb" wait-for-device
DEVICE_COUNT=$("$ANDROID_HOME/platform-tools/adb" devices | tail -n +2 | grep -c '\Sdevice$' || true)
if [ "$DEVICE_COUNT" -eq 0 ]; then
  echo "FATAL: no emulator / device attached." >&2
  exit 1
fi

echo "=== :app:connectedDebugAndroidTest ==="
( cd "$ANDROID_APP" && ./gradlew :app:connectedDebugAndroidTest )

echo
echo "SUCCESS. Test reports at:"
echo "  $ANDROID_APP/app/build/reports/androidTests/connected/"
```

- [ ] **Step 2: Write `verify.sh`**

```bash
#!/usr/bin/env bash
#
# CI / local one-shot. Build the bits, then run the emulator smoke.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$HERE/build.sh"
"$HERE/run-emulator.sh"
```

- [ ] **Step 3: Mark executable + commit**

Run:
```bash
chmod +x examples/observable-counter/run-emulator.sh examples/observable-counter/verify.sh
git add examples/observable-counter/run-emulator.sh examples/observable-counter/verify.sh
git commit -m "feat(observable-counter): add run-emulator.sh + verify.sh"
```

### Task 16: Local end-to-end verification via `verify.sh`

**Files:**
- (No files; verification only.)

- [ ] **Step 1: Boot the emulator**

(Separate terminal:)
```bash
$ANDROID_HOME/emulator/emulator -avd <arm64-v8a API 34 AVD name>
```

- [ ] **Step 2: Run `verify.sh`**

Run: `./examples/observable-counter/verify.sh`
Expected: ends with `SUCCESS. Test reports at: …`. The instrumented test
result must be `addBurstReachesExpectedSnapshot ✔`.

- [ ] **Step 3: No commit** — verification only.

---

## Phase 4E: CI emulator job

### Task 17: `examples.yml` — add `observable-counter-emulator` job

**Files:**
- Modify: `.github/workflows/examples.yml`

The new job sits alongside the existing `cross-roundtrip` job and is
gated to `ubuntu-latest` because the `reactivecircus/android-emulator-runner`
action requires KVM which is only available on Linux runners. The job's
steps mirror `verify.sh` but install the Android Swift SDK as an extra
setup step.

The matching Android Swift SDK download URL is published on swift.org's
install page. Look up the URL for `swift-6.3.2-RELEASE` Android aarch64
artifactbundle at <https://www.swift.org/install/> — at time of writing
it is hosted under `download.swift.org/swift-6.3.2-release/android-aarch64/`.
Copy the URL into the workflow step; do not hard-code it elsewhere.

- [ ] **Step 1: Append the job**

Edit `.github/workflows/examples.yml` to add a second job below the
existing `cross-roundtrip` job:

```yaml
  observable-counter-emulator:
    name: examples/observable-counter (emulator smoke)
    runs-on: ubuntu-latest
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v4

      - name: Enable KVM
        run: |
          echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' \
            | sudo tee /etc/udev/rules.d/99-kvm4all.rules
          sudo udevadm control --reload-rules
          sudo udevadm trigger --name-match=kvm

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '17'

      - name: Install Swift
        uses: swift-actions/setup-swift@v2
        with:
          swift-version: '6.3.2'

      - name: Install Swift Android SDK
        env:
          # Find the matching artifactbundle URL on https://www.swift.org/install/
          # for swift-6.3.2-RELEASE Android aarch64.
          SDK_URL: https://download.swift.org/swift-6.3.2-release/android-aarch64/swift-6.3.2-RELEASE/swift-6.3.2-RELEASE-android-aarch64-0.1.artifactbundle.tar.gz
        run: |
          swift sdk install "$SDK_URL"
          swift sdk list

      - name: Set up Gradle
        uses: gradle/actions/setup-gradle@v3

      - name: Cache AVD
        uses: actions/cache@v4
        id: avd-cache
        with:
          path: |
            ~/.android/avd/*
            ~/.android/adb*
          key: avd-api-34-arm64-v8a

      - name: Create AVD if not cached
        if: steps.avd-cache.outputs.cache-hit != 'true'
        uses: reactivecircus/android-emulator-runner@v2
        with:
          api-level: 34
          arch: arm64-v8a
          target: google_apis
          force-avd-creation: false
          emulator-options: -no-window -gpu swiftshader_indirect -noaudio -no-boot-anim -camera-back none
          disable-animations: true
          script: echo "AVD created"

      - name: Run verify.sh on emulator
        uses: reactivecircus/android-emulator-runner@v2
        with:
          api-level: 34
          arch: arm64-v8a
          target: google_apis
          force-avd-creation: false
          emulator-options: -no-window -gpu swiftshader_indirect -noaudio -no-boot-anim -camera-back none
          disable-animations: true
          script: ./examples/observable-counter/verify.sh

      - name: Upload test reports on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: observable-counter-test-reports
          path: examples/observable-counter/android-app/app/build/reports/androidTests/connected/
```

The exact Swift Android SDK artifactbundle URL must be confirmed against
swift.org at the time of the change. If the URL guess above is wrong the
`swift sdk install` step prints a 404; the engineer must look up the
current canonical URL on swift.org install page and update the workflow.

- [ ] **Step 2: Validate workflow YAML**

Run: `yq '.jobs | keys' .github/workflows/examples.yml`
Expected: an array containing `cross-roundtrip` and
`observable-counter-emulator`.

If `yq` is not installed, fall back to `python3 -c 'import yaml,sys; yaml.safe_load(open("/dev/stdin")); print("OK")' < .github/workflows/examples.yml`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/examples.yml
git commit -m "ci(observable-counter): add emulator smoke job"
```

The CI job will only run on push / PR, so verifying it green requires
opening the eventual PR or pushing to a feature branch. Do not block
Phase 4 completion on the CI job's first green; the local verify.sh
pass from Task 16 is the primary evidence the example works.

---

## Phase 4F: Conformance fixture

### Task 18: `ObservableBurstFixtureGenerator` (Swift, disabled-by-default)

**Files:**
- Create: `Tests/ConformanceTests/ObservableBurstFixtureGenerator.swift`

The fixture encodes the canonical "10-element TodoItem list after the
`add ×10` burst" as a wire-format byte array — exactly the same bytes
the macro-generated `__items_track` JNI bridge would return after the
burst settles. The Kotlin conformance test re-decodes it and asserts
the list shape matches the matching `.json`.

Match the existing pattern from
`Tests/ConformanceTests/GenerateFixtures.swift` — `@Test(.disabled(...))`
so the file is generated on demand but does not slow normal `swift test`
runs.

- [ ] **Step 1: Inspect the existing pattern**

Read `Tests/ConformanceTests/GenerateFixtures.swift` end-to-end. Note
the helper that writes both `.bin` and `.json` to
`kotlin/conformance-tests/fixtures/`. The new generator mirrors it.

- [ ] **Step 2: Write the generator**

```swift
import Foundation
import Testing
@testable import Wirelet

/// Regenerates `observable_burst_v1.{bin,json}`. Disabled by default;
/// run manually when the wire-format for `TodoItem` or `WireletList`
/// shifts.
///
///     swift test \
///       --filter ObservableBurstFixtureGenerator \
///       --enable-disabled-tests
@Suite
struct ObservableBurstFixtureGenerator {

    @Test(.disabled("Run manually to regenerate fixture."))
    func regenerate() throws {
        // The burst sequence produces 10 TodoItem entries: id=1..10,
        // title="task #1".."task #10", done=false on each.
        struct TodoItem: Equatable {
            var id: Int32
            var title: String
            var done: Bool
        }
        let items: [TodoItem] = (1...10).map { i in
            TodoItem(id: Int32(i), title: "task #\(i)", done: false)
        }

        // Encode each TodoItem inline using the same TLV layout the
        // generated Kotlin TodoItemCodec.encodePayload produces. The
        // encode order mirrors the declaration order in TodoItem.swift:
        // id (Int32), title (String), done (Bool).
        var writer = WireFormatWriter()
        writer.writeVarint(UInt64(items.count))
        for item in items {
            var inner = WireFormatWriter()
            inner.writeI32(item.id)
            inner.writeString(item.title)
            inner.writeBool(item.done)
            writer.writeBytes(inner.data)
        }

        let bin = writer.data
        let binPath = fixturesDir.appendingPathComponent("observable_burst_v1.bin")
        try bin.write(to: binPath)

        let json = """
        {
          "items": [
            \(items.map { """
                {"id": \($0.id), "title": "\($0.title)", "done": \($0.done)}
              """ }.joined(separator: ",\n    "))
          ]
        }

        """
        let jsonPath = fixturesDir.appendingPathComponent("observable_burst_v1.json")
        try json.write(to: jsonPath, atomically: true, encoding: .utf8)
    }

    private var fixturesDir: URL {
        // Tests/ConformanceTests/<this file>.swift → repo root → kotlin/...
        let here = URL(fileURLWithPath: #filePath)
        return here
            .deletingLastPathComponent()  // ConformanceTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // <repo>/
            .appendingPathComponent("kotlin/conformance-tests/fixtures")
    }
}
```

- [ ] **Step 3: Regenerate**

Run:
```bash
swift test \
  --filter ObservableBurstFixtureGenerator \
  --enable-disabled-tests
```
Expected: the test passes; `git status` shows the two new files.

If the `--enable-disabled-tests` flag is not honored by the Swift Testing
version pinned, the existing `GenerateFixtures.swift` uses a different
gating idiom (e.g. an environment variable). Match that idiom in the
new file so a single command regenerates both legacy fixtures and this
new one.

- [ ] **Step 4: Commit the generator + the generated files**

```bash
git add Tests/ConformanceTests/ObservableBurstFixtureGenerator.swift \
  kotlin/conformance-tests/fixtures/observable_burst_v1.bin \
  kotlin/conformance-tests/fixtures/observable_burst_v1.json
git commit -m "test(observable-counter): add observable_burst_v1 conformance fixture"
```

### Task 19: `FixtureRunner.kt` — decode `observable_burst_v1`

**Files:**
- Modify: `kotlin/conformance-tests/src/test/kotlin/io/github/jiyimeta/wirelet/conformance/FixtureRunner.kt`

- [ ] **Step 1: Inspect the existing fixture pattern**

Read the file's existing tests (e.g. `primitives()`). Note how it
locates fixtures (`fixture("primitives_v1.bin")`), decodes via a
generated codec, asserts canonical values, then re-encodes and asserts
byte-equality.

- [ ] **Step 2: Add the new test**

Append (or insert near the other tests):

```kotlin
@Test
fun observableBurst() {
    val bytes = fixture("observable_burst_v1.bin")
    val items = WireletList.decode(bytes, TodoItemCodec::decodePayload)
    assertEquals(10, items.size)
    items.forEachIndexed { idx, item ->
        assertEquals((idx + 1).toInt(), item.id)
        assertEquals("task #${idx + 1}", item.title)
        assertEquals(false, item.done)
    }
    val reencoded = WireletList.encode(items, TodoItemCodec::encodePayload)
    assertContentEquals(bytes, reencoded)
}
```

`TodoItemCodec` here is the conformance-test-local generated codec. The
conformance tests already wire up their own schema generation pass; add
`TodoItem.swift` to the schema sources for the conformance test if it is
not already produced by the existing pass. (Inspect
`kotlin/conformance-tests/build.gradle.kts` and the existing fixture
schemas to see how to register a new struct.)

If the conformance-tests harness reuses fixtures from the existing
`Tests/ConformanceTests/Fixtures/`, mirror that layout: add a Swift
schema file declaring `TodoItem` so the Kotlin emitter generates
`TodoItemCodec` for the test.

- [ ] **Step 3: Run conformance tests**

Run: `kotlin/gradlew :conformance-tests:test`
Expected: `BUILD SUCCESSFUL`; the new `observableBurst` test passes.

- [ ] **Step 4: Commit**

```bash
git add kotlin/conformance-tests/
git commit -m "test(observable-counter): conformance fixture decode roundtrips observable_burst_v1"
```

---

## Phase 4G: Docs

### Task 20: README + getting-started touch-ups

**Files:**
- Modify: `README.md`
- Modify: `docs/getting-started-swift.md`
- Modify: `docs/getting-started-kotlin.md`

These are short additive changes — they point to the example and the
Phase 4 design doc rather than duplicating content.

- [ ] **Step 1: Update root `README.md`**

In the existing "Examples" section (or wherever `cross-roundtrip` is
listed), add a sibling row:

```markdown
- `examples/observable-counter/` — end-to-end Observable bridge demo. A
  Swift `@WireletObservable @Observable` class is bridged to an Android
  Compose app whose UI collects the generated `StateFlow` properties.
  See [Phase 4 plan](docs/superpowers/plans/2026-05-29-wirelet-observable-bridge-phase-4.md).
```

- [ ] **Step 2: Update `docs/getting-started-swift.md`**

Add a short section at the end (above any existing "Next steps" /
"See also"):

```markdown
## Observable bridge

For exposing a live `@Observable` Swift class to Kotlin as an Android
`ViewModel` with `StateFlow<T>` properties, pair `@WireletObservable`
with `@Observable`:

    @WireletObservable
    @Observable
    public final class CounterVM {
        public var count: Int32 = 0
        @WireletExpose public func increment() { count += 1 }
    }

The macro emits `@_cdecl` JNI bridges under `#if os(Android)`; Apple
builds compile the macro to nothing. A full end-to-end example lives at
`examples/observable-counter/`.
```

- [ ] **Step 3: Update `docs/getting-started-kotlin.md`**

Add a parallel section pointing at the example + plugin DSL:

```markdown
## Observable view-models

The `io.github.jiyimeta.wirelet` plugin grows an `observable { ... }`
block that generates one `<Name>ViewModel.kt` per Swift
`@WireletObservable` class. Each generated VM exposes one
`StateFlow<T>` per Swift stored property and is wired into
`androidx.lifecycle.ViewModel`. See `examples/observable-counter/` for a
complete Compose app that consumes the generated view-model.
```

- [ ] **Step 4: Commit**

```bash
git add README.md docs/getting-started-swift.md docs/getting-started-kotlin.md
git commit -m "docs(observable-counter): link example from README + getting-started guides"
```

---

## Phase 4H: Full-suite verification

### Task 21: Full repo verification

- [ ] **Step 1: Swift tests**

Run: `swift test`
Expected: all existing + Phase 4 conformance generator tests pass (the
disabled fixture generator is skipped by default — no failure).

- [ ] **Step 2: Kotlin tests**

Run: `kotlin/gradlew check`
Expected: `BUILD SUCCESSFUL`. The new conformance burst test passes.

- [ ] **Step 3: Example end-to-end**

Run: `./examples/observable-counter/verify.sh` against a booted
emulator (see Task 16).
Expected: `SUCCESS. Test reports at: …`. Test report shows the burst
test passed.

- [ ] **Step 4: CI workflow lint**

Run: `python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/examples.yml")); print("OK")'`
Expected: prints `OK`.

- [ ] **Step 5: Clean tree**

Run: `git status`
Expected: clean (no untracked or modified files beyond the expected
build artifacts gitignored in Task 1).

- [ ] **Step 6: No commit** — verification only.

---

## Self-review checklist (done)

- **Spec coverage** — Phase 4 covers design spec §"Phase 5 — `observable-counter` example" (line 524-528) and the deferred items the Phase 3 plan handed off (`observable_burst_v1` fixture, `examples.yml` emulator job). Phase 1/2/3 doc references say Phase 4 plan = `examples/observable-counter/` end-to-end with emulator smoke + emulator CI job + `observable_burst_v1.txt`; user-confirmed the fixture format diverges from the original `.txt` script idea in favor of the existing `.bin/.json` pair convention (Task 18 + 19). The plan is complete for that scope.

- **Placeholders** — Task 17 Step 1 contains a Swift Android SDK URL that requires confirmation against swift.org at execution time. This is *not* a "TBD" placeholder — the URL is concrete, but the design intentionally calls out that the engineer must verify it; the failure mode is well-defined (404 on `swift sdk install`). Task 19 Step 2 also leaves the choice between "reuse existing conformance fixture schema pass" vs "add a new schema file" to the engineer's read of the conformance-test layout — both options are described with where to look; the right answer depends on local code state that may evolve before the plan executes.

- **Type consistency** — `libraryName.set("ObservableCounterJNI")` (Task 6) matches the `System.loadLibrary("ObservableCounterJNI")` call the Phase 3 emitter produces in `TodoListVMViewModel.kt`, which matches the staged `libObservableCounterJNI.so` filename (Tasks 4, 11, 14). The viewModel/model/codec package triplet (Task 6) lines up with the `import` lines in `MainActivity.kt` and `TodoScreen.kt` (Task 10). The `add` / `clear` `@WireletExpose` method names (Task 3) line up with the `vm.add(...)` / `vm::clear` references in the Compose UI (Task 10) and the burst test (Task 12). The fixture's `TodoItem` field order (Task 18: id, title, done) matches the Swift struct field order (Task 2) — crucial for the byte-equal re-encode assertion in Task 19.

- **Scope** — single subsystem (one Android example + its emulator CI + one conformance fixture). Independent of Phase 5 (publish + README feature-section). Can be merged on its own — the example runs locally, the CI job's first run is the smoke; if the emulator job is flaky, Phase 5 already plans a README pass that can include a recovery note. Mergable in isolation.

---

## What lands after this plan

1. **Phase 5 plan** — README "Observable bridge" feature section, swap the `0.0.1-local` sentinel for `0.2.0-SNAPSHOT` then the released `0.2.0`, wire `wirelet-observable-runtime` into `publish.yml`, cut the `v0.2.0` tag.
2. Optional: factor a `wirelet-observable-core` (no AndroidX) out of `wirelet-observable-runtime` if a non-Android consumer surfaces (per design spec deferred items).
