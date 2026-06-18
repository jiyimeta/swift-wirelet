# Contributing to swift-wirelet

Thanks for your interest in contributing. swift-wirelet is a
Swift-macro-driven wire-format toolkit that produces byte-identical
codecs for Swift and Kotlin from a single `@WireFormat` declaration, plus
the Observable and Provided JNI bridges. Because both sides of the wire
must stay byte-compatible, contributions are held to the conformance and
lint gates described below.

By participating you agree to abide by our
[Code of Conduct](CODE_OF_CONDUCT.md).

## Prerequisites

- A Swift toolchain capable of building the package (SwiftPM).
- A JDK for the Kotlin side; the repo ships a Gradle wrapper at
  `./kotlin/gradlew`, so you do not need a system Gradle install.
- The formatting/linting toolchain plus [pre-commit](https://pre-commit.com):

  ```bash
  brew install pre-commit swiftlint swiftformat
  ```

## One-time setup

This repo enforces formatting and linting through a pre-commit hook
(SwiftFormat, then SwiftLint `--fix`, then SwiftLint `--strict`). Install
the hook once per clone so every commit is checked locally:

```bash
pre-commit install
```

You can run the hooks across the whole tree at any time:

```bash
pre-commit run --all-files
```

The same checks run in CI (the **Lint** workflow), so installing the hook
locally is the fastest way to keep your branch green.

## Local verification

Run the same three commands CI runs before opening a PR:

```bash
# Swift side — runtime + macros + emitter + schema + CLI + conformance
swift test

# Kotlin side — runtime + conformance + Gradle plugin functional tests
./kotlin/gradlew -p kotlin check

# Cross-language smoke (Swift encoder → JVM decoder via the runtime)
./examples/cross-roundtrip/verify.sh
```

If you change anything that affects the wire format, the cross-language
conformance suite (`kotlin/conformance-tests/` and the Swift
`ConformanceTests`) is the source of truth — Swift writes `.bin` fixtures
and Kotlin decodes and re-encodes them, asserting byte equality. Both
sides must agree.

## Do not reformat fixtures

Files under any `**/Fixtures` directory (for example
`Tests/WireletSchemaTests/Fixtures/`) are **parsed as text** by the
schema parser — type annotations and `= nil` defaults are significant,
so a reformat can silently change what the parser sees. These paths are
excluded from SwiftFormat and SwiftLint on purpose (see
`.pre-commit-config.yaml` and the lint configs). Never hand-format or run
a formatter over fixture files, and do not add them to a formatter's
input.

## Commit message style

This repo uses [Conventional Commits](https://www.conventionalcommits.org/).
Prefix each commit with one of:

- `feat:` — a new feature
- `fix:` — a bug fix
- `docs:` — documentation only
- `refactor:` — a code change that neither fixes a bug nor adds a feature
- `chore:` — tooling, dependencies, or housekeeping
- `ci:` — CI configuration and workflows

An optional scope is encouraged, e.g. `feat(kotlin-emitter): …` or
`fix(plugin): …`. Keep the subject line concise and in the imperative
mood.

## Pull request workflow

1. Fork the repository and create a topic branch off `main`.
2. Make your changes, with tests where it makes sense. New Swift tests
   use Swift Testing unless the surrounding suite already uses XCTest
   (the macro-expansion suites do, because `assertMacroExpansion` is
   XCTest-based).
3. For any user-facing change, add an entry under the **Unreleased**
   heading in [CHANGELOG.md](CHANGELOG.md).
4. Ensure the pre-commit hook passes and that the three local
   verification commands above are green.
5. Open a PR against `main` and describe the change and its motivation.
   Reference any related issue.
6. Wait for review from the maintainer (@jiyimeta) and address feedback.

CI runs the following checks on every PR; please get them green before
requesting review:

- **Lint** — SwiftFormat + SwiftLint `--strict`
- **Swift** — the SwiftPM test suite (`swift test`)
- **Kotlin** — `./kotlin/gradlew -p kotlin check`
- **Conformance** — the cross-language byte-equality suite
- **Examples** — the example packages, including the cross-roundtrip smoke

Keep PRs focused; unrelated changes are easier to review when split
apart.

## Reporting bugs and proposing changes

Open a GitHub issue describing the problem or proposal. For a bug,
include the wire-format type or bridge involved and a minimal repro where
possible — a failing conformance fixture is ideal.

To report a security vulnerability, please **do not** open a public
issue. See [SECURITY.md](SECURITY.md) for the private reporting process.
