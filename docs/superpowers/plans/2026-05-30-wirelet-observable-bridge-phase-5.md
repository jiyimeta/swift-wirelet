# Wirelet Observable Bridge — Phase 5: v0.2.0 release (publish + README + tag)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cut the `v0.2.0` release that exposes the Observable bridge to consumers. Specifically: (1) wire `wirelet-observable-runtime` into the tag-triggered `publish.yml` workflow so the artifact lands on GitHub Packages alongside `wirelet-runtime` and `wirelet-gradle-plugin`; (2) swap the `0.0.1-local` `publishToMavenLocal` sentinel for `0.2.0-SNAPSHOT` across every example script + Gradle file so local example builds resolve against the same artifact set CI publishes; (3) add a long-form "Observable bridge" feature section to the top-level `README.md` describing what the bridge does, the moving parts, and a minimal "how to use" trio (Swift class → `observable { }` Gradle DSL → Compose collect site); (4) update the `README.md` Status line and the Pinned coordinates table to `v0.2.0`, adding the new `wirelet-observable-runtime` Maven row; (5) verify the `examples/observable-counter (emulator smoke)` CI job — added in Phase 4 but never green-run — passes against the SNAPSHOT version on `main`; (6) cut and push the `v0.2.0` tag, which fires `publish.yml` and lands the three artifacts on GitHub Packages plus a generated GitHub Release.

**Architecture:**
- **No code changes.** This is a release-engineering phase. The Observable bridge implementation is already complete (Phase 1-4 + multi-arg follow-up). What's missing is the version metadata that turns local builds into a consumable release.
- **Version flow.** `kotlin/runtime/build.gradle.kts`, `kotlin/observable-runtime/build.gradle.kts`, and `kotlin/gradle-plugin/build.gradle.kts` all read `version = (findProperty("wireletVersion") as String?) ?: "0.0.0-SNAPSHOT"`. Examples invoke `./gradlew :…:publishToMavenLocal -PwireletVersion=<value>` and then reference `io.github.jiyimeta:wirelet-runtime:<value>` etc. in their app `build.gradle.kts`. The string used in the `-P` flag must match the dependency coordinate string for `~/.m2` resolution to work. Today every example uses `0.0.1-local`; after this phase they all use `0.2.0-SNAPSHOT`. The release-time `publish.yml` continues to pass `-PwireletVersion=${tag#v}`, so the published artifact's version is `0.2.0` (taken from the `v0.2.0` tag).
- **Publish workflow extension.** The existing `Publish wirelet-runtime + wirelet gradle-plugin` step in `.github/workflows/publish.yml` already does `:runtime:publishAllPublicationsToGitHubPackagesRepository` and `:gradle-plugin:publishAllPublicationsToGitHubPackagesRepository`. The `kotlin/observable-runtime/build.gradle.kts` module already declares an equivalent publishing block (artifactId `wirelet-observable-runtime`, GitHubPackages repo `https://maven.pkg.github.com/jiyimeta/swift-wirelet`). We add `:observable-runtime:publishAllPublicationsToGitHubPackagesRepository` to the same step's gradle invocation, and update the step name to reflect the third artifact.
- **README structure.** The current README has the sections: `# swift-wirelet` → preamble → Pinned coordinates → `## At a glance` → `## Architecture` → `## Repository layout` → `## Getting started` → `## Quick local verification` → `## License`. We insert a new `## Observable bridge` section between `## Architecture` and `## Repository layout`, mirroring the level of detail in the existing `## At a glance` section (one paragraph of prose, one Swift snippet, one Kotlin snippet, one short "what gets generated" list). The "Status" line in the preamble and the "Pinned coordinates" table are updated in the same commit.
- **Tag cut.** Tags use `v<semver>` format. `v0.1.0-alpha.1` and `v0.1.0-alpha.2` are existing tags. `v0.2.0` jumps past the unused `v0.1.0` slot — intentional, per the design retrospective's "after Phase 4 we go directly to v0.2.0" stance. Push the annotated tag; `publish.yml` triggers on `push: tags: ['v*']`. Optionally precede with `git tag --sign` if commit signing is configured (verify before assuming).

**Tech Stack:** Gradle 8.x (`maven-publish`), GitHub Actions (`publish.yml`, `examples.yml`), GitHub Packages Maven repo (`maven.pkg.github.com/jiyimeta/swift-wirelet`), `softprops/action-gh-release@v2` for the Release artifact, Markdown (CommonMark) for `README.md`.

---

## File Structure

Files modified by this plan:

- `.github/workflows/publish.yml` — add `:observable-runtime:publishAllPublicationsToGitHubPackagesRepository` to the publish step, and rename the step.
- `examples/observable-counter/build.sh` — version sentinel `0.0.1-local` → `0.2.0-SNAPSHOT` (line 28).
- `examples/observable-counter/android-app/build.gradle.kts` — sentinel swap (line 5).
- `examples/observable-counter/android-app/app/build.gradle.kts` — sentinel swap (lines 69, 70).
- `examples/cross-roundtrip/verify.sh` — sentinel swap (line 22).
- `examples/cross-roundtrip/jvm-decoder/build.gradle.kts` — sentinel swap (line 12).
- `README.md` — add `## Observable bridge` section; update `**Status**` line; update `Pinned coordinates` table (add the third row).

No new files. No removed files.

---

## Phase 5A: Wire `wirelet-observable-runtime` into `publish.yml`

### Task 1: Add `:observable-runtime:publishAllPublicationsToGitHubPackagesRepository` to the publish step

**Files:**
- Modify: `.github/workflows/publish.yml:54-63`

- [ ] **Step 1: Edit the publish step**

Replace the existing block (lines 54-63):

```yaml
      - name: Publish wirelet-runtime + wirelet gradle-plugin
        working-directory: kotlin
        env:
          GITHUB_ACTOR: ${{ github.actor }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          ./gradlew \
            -PwireletVersion=${{ steps.version.outputs.version }} \
            :runtime:publishAllPublicationsToGitHubPackagesRepository \
            :gradle-plugin:publishAllPublicationsToGitHubPackagesRepository
```

with:

```yaml
      - name: Publish wirelet-runtime + observable-runtime + wirelet gradle-plugin
        working-directory: kotlin
        env:
          GITHUB_ACTOR: ${{ github.actor }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          ./gradlew \
            -PwireletVersion=${{ steps.version.outputs.version }} \
            :runtime:publishAllPublicationsToGitHubPackagesRepository \
            :observable-runtime:publishAllPublicationsToGitHubPackagesRepository \
            :gradle-plugin:publishAllPublicationsToGitHubPackagesRepository
```

- [ ] **Step 2: Sanity-check the YAML parses**

Run from repo root:

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/publish.yml'))"
```

Expected: exits 0, no output.

(If PyYAML is missing, fall back to `gh workflow view publish` after the commit — GitHub will surface a parse error.)

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/publish.yml
git commit -m "ci(publish): publish wirelet-observable-runtime alongside runtime + plugin"
```

---

## Phase 5B: Swap `0.0.1-local` sentinel for `0.2.0-SNAPSHOT`

The sentinel is referenced by two examples (six files total). All callers must update together — `-PwireletVersion=X` writes the artifact to `~/.m2/.../X/`, and the consumer dependency line resolves `…:X` from the same path.

### Task 2: Swap sentinel in `examples/observable-counter`

**Files:**
- Modify: `examples/observable-counter/build.sh:28`
- Modify: `examples/observable-counter/android-app/build.gradle.kts:5`
- Modify: `examples/observable-counter/android-app/app/build.gradle.kts:69-70`

- [ ] **Step 1: Edit `build.sh`**

Change line 28 from:

```bash
  -PwireletVersion=0.0.1-local \
```

to:

```bash
  -PwireletVersion=0.2.0-SNAPSHOT \
```

- [ ] **Step 2: Edit `android-app/build.gradle.kts`**

Change line 5 from:

```kotlin
    id("io.github.jiyimeta.wirelet") version "0.0.1-local" apply false
```

to:

```kotlin
    id("io.github.jiyimeta.wirelet") version "0.2.0-SNAPSHOT" apply false
```

- [ ] **Step 3: Edit `android-app/app/build.gradle.kts`**

Change lines 69-70 from:

```kotlin
    implementation("io.github.jiyimeta:wirelet-runtime:0.0.1-local")
    implementation("io.github.jiyimeta:wirelet-observable-runtime:0.0.1-local")
```

to:

```kotlin
    implementation("io.github.jiyimeta:wirelet-runtime:0.2.0-SNAPSHOT")
    implementation("io.github.jiyimeta:wirelet-observable-runtime:0.2.0-SNAPSHOT")
```

- [ ] **Step 4: Verify no `0.0.1-local` left under `examples/observable-counter/`**

Run:

```bash
grep -rn "0.0.1-local" examples/observable-counter/
```

Expected: no matches.

- [ ] **Step 5: Commit**

```bash
git add examples/observable-counter/build.sh \
        examples/observable-counter/android-app/build.gradle.kts \
        examples/observable-counter/android-app/app/build.gradle.kts
git commit -m "chore(observable-counter): swap 0.0.1-local sentinel for 0.2.0-SNAPSHOT"
```

### Task 3: Swap sentinel in `examples/cross-roundtrip`

**Files:**
- Modify: `examples/cross-roundtrip/verify.sh:22`
- Modify: `examples/cross-roundtrip/jvm-decoder/build.gradle.kts:12`

- [ ] **Step 1: Edit `verify.sh`**

Change line 22 from:

```bash
    -PwireletVersion=0.0.1-local \
```

to:

```bash
    -PwireletVersion=0.2.0-SNAPSHOT \
```

- [ ] **Step 2: Edit `jvm-decoder/build.gradle.kts`**

Change line 12 from:

```kotlin
    implementation("io.github.jiyimeta:wirelet-runtime:0.0.1-local")
```

to:

```kotlin
    implementation("io.github.jiyimeta:wirelet-runtime:0.2.0-SNAPSHOT")
```

- [ ] **Step 3: Verify no `0.0.1-local` left under `examples/cross-roundtrip/`**

Run:

```bash
grep -rn "0.0.1-local" examples/cross-roundtrip/
```

Expected: no matches.

- [ ] **Step 4: Commit**

```bash
git add examples/cross-roundtrip/verify.sh examples/cross-roundtrip/jvm-decoder/build.gradle.kts
git commit -m "chore(cross-roundtrip): swap 0.0.1-local sentinel for 0.2.0-SNAPSHOT"
```

### Task 4: Sanity-check both examples still build

The version swap is mechanical, but it's the kind of change that's catastrophic if a stray reference is left and the local Maven resolve fails halfway through `assembleDebug`. Local smoke before pushing.

- [ ] **Step 1: Run cross-roundtrip verify**

Run from repo root:

```bash
./examples/cross-roundtrip/verify.sh
```

Expected: ends with `PASS: cross-roundtrip` (or whatever the existing success line is). If it fails on a Maven resolve, grep again for `0.0.1-local` — likely a missed file.

- [ ] **Step 2: Run observable-counter build (skip emulator phase locally)**

Run from repo root:

```bash
./examples/observable-counter/build.sh
```

Expected: produces `examples/observable-counter/android-app/app/build/outputs/apk/debug/app-debug.apk` without errors. (Do NOT run `run-emulator.sh` here — the CI emulator job is the source of truth, see Phase 5E.)

- [ ] **Step 3: Confirm no `0.0.1-local` remains anywhere in tracked source**

Run:

```bash
git ls-files | xargs grep -l "0.0.1-local" 2>/dev/null
```

Expected: only `docs/superpowers/plans/` files (historical plan docs). No live `.sh` / `.gradle.kts` / `.yml` / `.md` files outside the plans directory should match. If any do, swap them and amend the relevant commit.

---

## Phase 5C: README "Observable bridge" feature section

### Task 5: Insert long-form `## Observable bridge` section

**Files:**
- Modify: `README.md` — insert a new `## Observable bridge` section between the existing `## Architecture` block (ends at line 105) and `## Repository layout` (starts at line 107).

- [ ] **Step 1: Insert the section**

After the closing `## Architecture` block (the line `[`docs/wire-format-spec.md`](docs/wire-format-spec.md) for byte layout.` followed by a blank line), add:

```markdown
## Observable bridge

`@WireletObservable` extends the `@WireFormat`-driven IPC pipeline to live
view-model state. Declare an `@Observable` Swift class once; cross-compile
it into a JNI `.so` for `aarch64-unknown-linux-android28`; consume it from
an Android Compose app as a Kotlin `ViewModel` whose properties are
`StateFlow<T>`s. Mutations on the Swift side propagate to Kotlin
collectors via JNI callbacks driven by Apple's Observation framework.

```swift
import Observation
import WireletObservable

@WireletObservable
@Observable
public final class TodoListVM {
    public var items: [TodoItem] = []   // → StateFlow<List<TodoItem>>
    public var totalCount: Int32 = 0    // → StateFlow<Int>

    @WireletExpose
    public func add(_ item: TodoItem) {
        items.append(item)
        totalCount += 1
    }
}
```

```kotlin
// auto-generated TodoListVMViewModel.kt
class TodoListVMViewModel : ViewModel() {
    val items: StateFlow<List<TodoItem>> = …
    val totalCount: StateFlow<Int> = …
    fun add(item: TodoItem) { … }   // crosses JNI, mutates Swift state,
                                    //   observation pushes new StateFlow values
}

// Compose use site
@Composable
fun TodoScreen(vm: TodoListVMViewModel = viewModel()) {
    val items by vm.items.collectAsStateWithLifecycle()
    val total by vm.totalCount.collectAsStateWithLifecycle()
    // …
}
```

What gets generated:

- **Swift side** (compile time + SwiftPM build tool plugin):
  - A `@_cdecl` global function per observable property and per `@WireletExpose`
    method, emitted by the `WireletObservableBridges` build tool plugin.
  - A `JNI_OnLoad` entry point that registers every `@_cdecl` symbol via
    `RegisterNatives`, driven by a sidecar `.wirelet-observable-jni.json`
    written by the Wirelet Gradle plugin.
- **Kotlin side** (Gradle task, via `emit-wirelet-observable`):
  - `<Class>ViewModel.kt` — extends `androidx.lifecycle.ViewModel`,
    holds a long ptr to the Swift instance, exposes one `StateFlow<T>`
    per observable property and one regular fun per `@WireletExpose`.
  - `<WireFormat>Codec.kt` for any wire-format types referenced in the
    view-model (same codec emitter as the base `@WireFormat` pipeline).

Wire it into a project by applying the `io.github.jiyimeta.wirelet`
Gradle plugin and adding an `observable { … }` block alongside the
existing `wirelet { … }` block — see
[`docs/getting-started-kotlin.md`](docs/getting-started-kotlin.md) for
the full DSL and
[`examples/observable-counter/`](examples/observable-counter/) for a
working Compose app.

```

(The fenced ` ```markdown ` block above is delimiter-only — the *content* between it and the closing triple-backtick is the new README section. When inserting, drop the outer ` ```markdown ` / ` ``` ` wrappers and place the inner content directly.)

- [ ] **Step 2: Render-check**

Run:

```bash
quick-md README.md
```

Expected: QuickMD opens; the new section renders with both code fences highlighted (Swift + Kotlin), the bullet list under "What gets generated" is well-formed, and the two cross-doc links (`docs/getting-started-kotlin.md`, `examples/observable-counter/`) underline as links.

(`quick-md` is a shell alias for `open -a QuickMD`.)

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(readme): add Observable bridge feature section"
```

---

## Phase 5D: README status line + pinned coordinates

### Task 6: Update the Status line

**Files:**
- Modify: `README.md:13-17`

- [ ] **Step 1: Edit the Status block**

Replace lines 13-17:

```markdown
**Status (2026-05-27):** pre-alpha, private repo. Phase 0-4 of the
extraction roadmap is shipped — runtime, macros, Kotlin emitter, Gradle
plugin, and the GitHub Actions publish pipeline are all green. Tags
`phase-1-complete` through `phase-4-complete` are pinned on `main`;
`v0.1.0-alpha.1` and `v0.1.0-alpha.2` are published to GitHub Packages.
```

with:

```markdown
**Status (2026-05-30):** pre-alpha, private repo. Phase 0-5 of the
extraction roadmap is shipped — runtime, macros, Kotlin emitter, Gradle
plugin, the Observable bridge (`@WireletObservable @Observable` →
Kotlin `ViewModel<StateFlow>` via JNI), and the GitHub Actions publish
pipeline are all green. Tags `phase-1-complete` through
`phase-5-complete` are pinned on `main`; `v0.1.0-alpha.1`,
`v0.1.0-alpha.2`, and `v0.2.0` are published to GitHub Packages.
```

- [ ] **Step 2: Edit the Pinned coordinates table**

Replace lines 21-25 (the table):

```markdown
| Surface | Identifier |
|---|---|
| SwiftPM dep | `.package(url: "git@github.com:jiyimeta/swift-wirelet.git", revision: "31be47c84fddf2834b3cccc05ff955dcd1f2668e")` (= `v0.1.0-alpha.2`) |
| Maven runtime | `io.github.jiyimeta:wirelet-runtime:0.1.0-alpha.2` |
| Gradle plugin | `id("io.github.jiyimeta.wirelet") version "0.1.0-alpha.2"` |
```

with (the SwiftPM `revision:` value is filled in at tag-cut time — see Phase 5F Task 11; for now mark it `TBD-fill-after-tag` and update before pushing the README commit):

```markdown
| Surface | Identifier |
|---|---|
| SwiftPM dep | `.package(url: "git@github.com:jiyimeta/swift-wirelet.git", revision: "<TBD-fill-after-tag>")` (= `v0.2.0`) |
| Maven runtime | `io.github.jiyimeta:wirelet-runtime:0.2.0` |
| Maven observable runtime | `io.github.jiyimeta:wirelet-observable-runtime:0.2.0` |
| Gradle plugin | `id("io.github.jiyimeta.wirelet") version "0.2.0"` |
```

Important: the `<TBD-fill-after-tag>` placeholder is the ONE exception to this plan's no-placeholders rule, because the SHA cannot be known until the tag's commit exists. Phase 5F Task 11 has the explicit step that fills it in. Do not commit the README until that step runs.

- [ ] **Step 3: Render-check**

Run:

```bash
quick-md README.md
```

Expected: the table now has four rows; the Status paragraph mentions Phase 0-5 and the new `v0.2.0` tag. The `<TBD-fill-after-tag>` string is visible — that is expected at this stage.

- [ ] **Step 4: Do NOT commit yet**

This file stays uncommitted until Phase 5F Task 11 fills the SHA in. Leave it staged for later. Stash-with-uncommitted-changes is fine; do not `git stash` because the rest of the workflow needs the working tree clean only for tag-cutting.

If you must commit (e.g. to keep the working tree clean before pushing other changes), commit it as-is with the placeholder and amend in Task 11 — annotate the commit message accordingly:

```bash
git add README.md
git commit -m "docs(readme): update Status + pinned coords for v0.2.0 (SHA TBD)"
```

Otherwise, leave it in the working tree.

---

## Phase 5E: Push to `main`, verify emulator CI green

Phase 4 added the `observable-counter-emulator` job to `.github/workflows/examples.yml`. It has never been run because Phase 4 was developed on a worktree branch. Pushing the SNAPSHOT-sentinel-swap commits to `main` triggers `examples.yml` (which runs on `push: branches: [main]`) and gives us first green.

### Task 7: Push the SNAPSHOT-swap branch to `main`

**Files:**
- No file changes. This task pushes the commits accumulated in Phase 5A + 5B + 5C.

- [ ] **Step 1: Verify current branch + status**

Run:

```bash
git status
git log --oneline -10
```

Expected: working tree has at most the uncommitted Phase 5D README change; `HEAD` is on top of Phase 5C's `docs(readme): add Observable bridge feature section` commit. The expected commit sequence (newest first) is:

```
docs(readme): add Observable bridge feature section
chore(cross-roundtrip): swap 0.0.1-local sentinel for 0.2.0-SNAPSHOT
chore(observable-counter): swap 0.0.1-local sentinel for 0.2.0-SNAPSHOT
ci(publish): publish wirelet-observable-runtime alongside runtime + plugin
…
```

(Phase 5D either is uncommitted in the working tree, or is committed as `docs(readme): update Status + pinned coords for v0.2.0 (SHA TBD)` — both are acceptable.)

- [ ] **Step 2: Push to `main`**

Run:

```bash
git push origin HEAD:main
```

Expected: push succeeds.

If working on a feature branch (e.g. `phase-5-release`), first PR-merge that into `main` instead of force-pushing — confirm the strategy with the user before pushing.

- [ ] **Step 3: Wait for `examples.yml` workflow run to complete**

Run:

```bash
gh run watch --workflow=examples.yml --exit-status
```

Or, manually:

```bash
gh run list --workflow=examples.yml --limit=3
gh run view <run-id>
```

Expected: both jobs pass — `examples/cross-roundtrip` and `examples/observable-counter (emulator smoke)`. The emulator job runtime is ~25-40 minutes (KVM cache prime + emulator boot + assembleDebug + connectedDebugAndroidTest). Cache hits on subsequent runs cut this to ~12-20 minutes.

If the emulator job fails:

- Pull the artifact: `gh run download <run-id> -n observable-counter-test-reports`
- Open `index.html` for the connected-test report.
- Common failure modes: emulator boot timeout (re-run; KVM cache is sometimes flaky on the first cold run), `UnsatisfiedLinkError` (the JNI sidecar is out of sync — investigate; this would block the tag), instrumented test assertion (a real Phase 4 bug that slipped through local testing — fix and re-push).

Do not proceed to Phase 5F until this job is green.

---

## Phase 5F: Cut `v0.2.0` tag, fill SHA, push README

### Task 8: Verify pre-tag state

Pre-flight before creating a tag that fires the publish workflow.

- [ ] **Step 1: Confirm `HEAD` matches the green CI commit**

Run:

```bash
git fetch --tags origin
git log origin/main..HEAD --oneline
git log HEAD..origin/main --oneline
```

Expected: both ranges are empty (local `main` and `origin/main` are aligned). If `HEAD..origin/main` has commits, someone else pushed — rebase before tagging. If `origin/main..HEAD` has commits, push them first.

- [ ] **Step 2: Confirm `v0.2.0` does not already exist**

Run:

```bash
git tag -l v0.2.0
git ls-remote --tags origin v0.2.0
```

Expected: both empty.

- [ ] **Step 3: Confirm the publish workflow's trigger pattern**

Run:

```bash
grep -A3 "^on:" .github/workflows/publish.yml
```

Expected: shows `push: tags: ['v*']`. The tag we create must match `v*` (it does).

### Task 9: Create the annotated `v0.2.0` tag

**Files:**
- No file changes.

- [ ] **Step 1: Create the tag**

Run:

```bash
git tag -a v0.2.0 -m "v0.2.0 — Observable bridge (Phase 5)

- @WireletObservable @Observable Swift class → Kotlin ViewModel<StateFlow>
  bridge over JNI.
- Multi-arg @WireletExpose methods (primitives + String + @WireFormat +
  Optional + Array).
- wirelet-observable-runtime Maven artifact (WireletList, lifecycle helpers).
- examples/observable-counter/ — full end-to-end Compose demo with
  CI emulator smoke."
```

(If commit signing is configured, the user's `commit.gpgsign=true` will add the signature automatically; do not pass `--no-gpg-sign`.)

- [ ] **Step 2: Confirm the tag exists locally**

Run:

```bash
git show v0.2.0 --stat | head -20
```

Expected: shows the tag annotation message and the commit it points to.

### Task 10: Push the tag — fires `publish.yml`

- [ ] **Step 1: Push**

Run:

```bash
git push origin v0.2.0
```

Expected: `* [new tag]         v0.2.0 -> v0.2.0`. Within seconds, `publish.yml` starts.

- [ ] **Step 2: Watch the publish run**

Run:

```bash
gh run watch --workflow=publish.yml --exit-status
```

Expected: workflow passes. The three artifacts land:

- `https://github.com/jiyimeta/swift-wirelet/packages` shows
  `wirelet-runtime`, `wirelet-observable-runtime`, and the Gradle-plugin
  Marker (`io.github.jiyimeta.wirelet.gradle.plugin`) at version `0.2.0`.
- A GitHub Release named `v0.2.0` is created with generated release notes.

If the workflow fails on the publish step:

- A common cause is a `wirelet-observable-runtime` version already existing
  in GitHub Packages (re-run / overwrite). GitHub Packages rejects overwrites
  of immutable Maven coordinates — delete the package version from the UI
  if you must retry, but check first whether the publish actually failed
  before retrying (the next step downloads the artifact to confirm).

### Task 11: Update README pinned coords with the real SHA

The README change from Phase 5D Task 6 has the SHA placeholder `<TBD-fill-after-tag>`. Now fill it in.

**Files:**
- Modify: `README.md:23` — replace `<TBD-fill-after-tag>` with the full 40-char commit SHA that `v0.2.0` points to.

- [ ] **Step 1: Resolve the tag's commit SHA**

Run:

```bash
git rev-parse v0.2.0^{commit}
```

Expected: prints a 40-char SHA, e.g. `a1b2c3d4e5f6…`. Copy it.

- [ ] **Step 2: Replace the placeholder**

In `README.md`, find:

```markdown
| SwiftPM dep | `.package(url: "git@github.com:jiyimeta/swift-wirelet.git", revision: "<TBD-fill-after-tag>")` (= `v0.2.0`) |
```

Replace `<TBD-fill-after-tag>` with the SHA from Step 1. The full line becomes (with the example SHA — substitute the real one):

```markdown
| SwiftPM dep | `.package(url: "git@github.com:jiyimeta/swift-wirelet.git", revision: "a1b2c3d4e5f6…")` (= `v0.2.0`) |
```

- [ ] **Step 3: Verify no `TBD-fill-after-tag` remains**

Run:

```bash
grep -n "TBD-fill-after-tag" README.md
```

Expected: no matches.

- [ ] **Step 4: Commit**

If Phase 5D was left uncommitted in the working tree:

```bash
git add README.md
git commit -m "docs(readme): update Status + pinned coords for v0.2.0"
```

If Phase 5D was already committed as `docs(readme): update Status + pinned coords for v0.2.0 (SHA TBD)`, amend it:

```bash
git add README.md
git commit --amend --no-edit -m "docs(readme): update Status + pinned coords for v0.2.0"
```

(Amending a not-yet-pushed commit is safe; if it was pushed, do not amend — make a new commit with subject `docs(readme): fill v0.2.0 commit SHA in pinned coords`.)

- [ ] **Step 5: Push the README update**

Run:

```bash
git push origin HEAD:main
```

Expected: push succeeds. This will trigger `examples.yml` again (push to main); the run is expected to pass against the now-released artifacts.

### Task 12: Tag `phase-5-complete`

The repo uses `phase-N-complete` tags to mark milestones (per the Status line wording). Add the matching one for Phase 5.

- [ ] **Step 1: Create + push**

```bash
git tag phase-5-complete v0.2.0
git push origin phase-5-complete
```

Expected: lightweight tag pushed. Does NOT fire `publish.yml` (the trigger is `tags: ['v*']`; `phase-5-complete` does not match).

- [ ] **Step 2: Verify**

```bash
git ls-remote --tags origin | grep -E "phase-5-complete|v0.2.0"
```

Expected: both tags appear on the remote.

---

## Phase 5G: Post-release smoke

Light verification that the published artifacts actually resolve from a clean state.

### Task 13: Verify GitHub Packages resolves the new artifacts

**Files:**
- No file changes.

- [ ] **Step 1: Clean the local example's mavenLocal cache for these artifacts**

Run:

```bash
rm -rf ~/.m2/repository/io/github/jiyimeta/wirelet-runtime/0.2.0 \
       ~/.m2/repository/io/github/jiyimeta/wirelet-observable-runtime/0.2.0 \
       ~/.m2/repository/io/github/jiyimeta/wirelet-gradle-plugin/0.2.0
```

(These directories likely don't exist anyway — the local examples use the `-SNAPSHOT` suffix — but clean is clean.)

- [ ] **Step 2: Confirm the artifacts exist on GitHub Packages**

Either through the UI (`https://github.com/jiyimeta/swift-wirelet/packages`) or via the API:

```bash
gh api /users/jiyimeta/packages?package_type=maven --jq '.[].name'
```

Expected: lists `io.github.jiyimeta.wirelet-runtime`, `io.github.jiyimeta.wirelet-observable-runtime`, `io.github.jiyimeta.wirelet-gradle-plugin` (the exact names may use dots vs hyphens — match against the existing patterns from the previous release).

- [ ] **Step 3: Confirm the GitHub Release page**

Run:

```bash
gh release view v0.2.0
```

Expected: prints the release page; `Title: v0.2.0`, body contains the auto-generated release notes from `softprops/action-gh-release@v2`.

- [ ] **Step 4: No commit — read-only verification.**

---

## Self-review checklist

- **Spec coverage** — Phase 5 covers the design spec §"Phase 5 — `observable-counter` example" (`docs/superpowers/specs/2026-05-29-wirelet-observable-bridge-design.md:524-528`) — specifically the "Wire CI emulator job" item (Phase 5E here verifies first green) and implicitly the release-engineering follow-up the Phase 4 retrospective spelled out as "Phase 5 plan" (`docs/superpowers/plans/2026-05-29-wirelet-observable-bridge-phase-4.md:1588-1591`). All four bullets from the retrospective (README section, `0.0.1-local` swap, `publish.yml` wiring, `v0.2.0` tag) are addressed by Tasks 1-12.

- **Placeholders** — The plan has exactly one intentional placeholder: the `<TBD-fill-after-tag>` SHA in the README pinned coordinates table (Phase 5D Task 6). This is not a plan deficiency — the SHA literally cannot be computed before the tag's commit exists. Phase 5F Task 11 explicitly fills it. No other placeholders, "TODO", or "fill in details" in the plan.

- **Type consistency** — Version string `0.2.0-SNAPSHOT` is used uniformly in `-PwireletVersion=…` flags and in dependency coordinate strings across Tasks 2 + 3 (the same value must appear in both contexts for `~/.m2` resolution to work). The release version `0.2.0` (no suffix) is used uniformly in the README pinned coords (Task 6) and the tag (`v0.2.0`, Task 9). Module names (`:observable-runtime`) and Maven artifactId (`wirelet-observable-runtime`) match the existing `kotlin/observable-runtime/build.gradle.kts:30` declaration. The tag annotation message (Task 9) mentions the same three published artifact names that Task 1's gradle invocation publishes.

- **Scope** — release-engineering only. No code changes to runtime, macros, emitters, or examples beyond the version sentinel string. Independent of any future feature work. Mergeable in one go — but the natural commit boundary is one commit per of (publish.yml CI, observable-counter sentinel, cross-roundtrip sentinel, README feature section, README pinned-coords), with the tag cut as the terminating action.

---

## What lands after this plan

1. `v0.2.0` is the first "general availability" release of swift-wirelet (`v0.1.0-alpha.*` were pre-release).
2. Optional follow-ups deferred from the design spec §"Deferred" (`docs/superpowers/specs/2026-05-29-wirelet-observable-bridge-design.md:538-541`):
   - Diff-based `List<T>` updates (`WireletListDiff`) — v0.3 at earliest.
   - Pure-KMP runtime (`wirelet-observable-core` / `…-androidx` split) — gated on a non-Android consumer surfacing.
   - `@WireletObservable` on actor types — blocked on Apple's Observation framework gaining actor isolation integration.
   - Nested `@WireletObservable`-of-`@WireletObservable` — lifecycle ownership story unclear; not in v0.x scope.
