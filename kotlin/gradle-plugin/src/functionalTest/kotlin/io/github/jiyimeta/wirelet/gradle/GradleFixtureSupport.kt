package io.github.jiyimeta.wirelet.gradle

import org.gradle.testkit.runner.GradleRunner
import java.io.File

/**
 * Resolves the wirelet repo root from the `wirelet.repoRoot` system
 * property exported by `build.gradle.kts`. TestKit fixtures need this so
 * that `wirelet.swiftPackagePath = file("...")` can point at the in-repo
 * Swift package.
 */
internal val wireletRepoRoot: File
    get() =
        File(
            System.getProperty("wirelet.repoRoot")
                ?: error("wirelet.repoRoot system property not set"),
        )

/**
 * Lays down a minimal Kotlin-JVM Gradle project under `dir`:
 *  - `settings.gradle.kts` with `pluginManagement` repos
 *  - `build.gradle.kts` applying `kotlin("jvm")` + the wirelet plugin
 *    plus the `buildScript` block extended with `swiftPackagePath`
 *
 * `extraBuildScript` is appended verbatim to `build.gradle.kts` after
 * the `plugins { ... }` block — use it to add the `wirelet { ... }`
 * configuration and any test-specific tasks.
 */
internal fun layoutFixture(
    dir: File,
    extraBuildScript: String,
) {
    dir.resolve("settings.gradle.kts").writeText(
        """
        rootProject.name = "wirelet-fixture"
        """.trimIndent(),
    )
    dir.resolve("build.gradle.kts").writeText(
        """
        plugins {
            kotlin("jvm") version "1.9.22"
            id("io.github.jiyimeta.wirelet")
        }
        repositories {
            mavenCentral()
        }
        $extraBuildScript
        """.trimIndent(),
    )
}

/**
 * Writes `content` to `<dir>/<relativePath>`, creating parent directories.
 */
internal fun writeSchemaFile(
    dir: File,
    relativePath: String,
    content: String,
) {
    val file = dir.resolve(relativePath)
    file.parentFile.mkdirs()
    file.writeText(content)
}

/**
 * Builds a `GradleRunner` rooted at `dir` with the plugin under test on
 * the classpath. JUnit and JDK assertions remain available in callers.
 */
internal fun runner(
    dir: File,
    vararg args: String,
): GradleRunner =
    GradleRunner.create()
        .withProjectDir(dir)
        .withPluginClasspath()
        .withArguments(*args, "--stacktrace")
        .forwardOutput()
