package io.github.jiyimeta.wirelet.gradle

import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ObservableAndCodecsCoexistTest {
    @Test
    fun bothTaskChainsRunWithDisjointOutputs(
        @TempDir tempDir: File,
    ) {
        layoutFixture(
            dir = tempDir,
            extraBuildScript =
                """
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
        writeSchemaFile(
            dir = tempDir,
            relativePath = "schema/Point.swift",
            content =
                """
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

        val result =
            runner(
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

        val codecFile =
            tempDir.resolve(
                "build/generated/wirelet/main/kotlin/" +
                    "com/example/fixture/codec/PointCodec.kt",
            )
        val viewModelFile =
            tempDir.resolve(
                "build/generated/wirelet/observable/main/kotlin/" +
                    "com/example/fixture/viewmodels/CounterViewModel.kt",
            )
        assertTrue(codecFile.exists(), "PointCodec missing: $codecFile")
        assertTrue(viewModelFile.exists(), "CounterViewModel missing: $viewModelFile")
    }
}
