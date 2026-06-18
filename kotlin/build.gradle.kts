plugins {
    kotlin("jvm") version "1.9.22" apply false
    id("org.jlleitschuh.gradle.ktlint") version "12.1.1" apply false
}

// ktlint is the Kotlin counterpart of SwiftFormat/SwiftLint on the Swift
// side: it formats and lints every module. Run `./gradlew ktlintFormat` to
// auto-fix and `./gradlew ktlintCheck` (wired into `check`) to verify.
subprojects {
    apply(plugin = "org.jlleitschuh.gradle.ktlint")

    configure<org.jlleitschuh.gradle.ktlint.KtlintExtension> {
        version.set("1.2.1")
    }
}
