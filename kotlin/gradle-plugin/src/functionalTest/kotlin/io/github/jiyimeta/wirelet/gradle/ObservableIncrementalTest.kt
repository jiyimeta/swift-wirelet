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
            relativePath = "schema/Counter.swift",
            content = """
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
            relativePath = "schema/Counter.swift",
            content = """
                import Observation
                import WireletObservable

                @WireletObservable
                @Observable
                public final class Counter {
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
