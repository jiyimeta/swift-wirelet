package io.github.jiyimeta.wirelet.gradle

import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ObservableSourceSetTest {
    @Test
    fun generatesViewModelKotlinForSimpleCounter(
        @TempDir tempDir: File,
    ) {
        layoutFixture(
            dir = tempDir,
            extraBuildScript =
                """
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
            relativePath = "schema/Counter.swift",
            content =
                """
                import Observation
                import WireletObservable

                @WireletObservable
                @Observable
                public final class Counter {
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
        val expectedVM =
            tempDir.resolve(
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
