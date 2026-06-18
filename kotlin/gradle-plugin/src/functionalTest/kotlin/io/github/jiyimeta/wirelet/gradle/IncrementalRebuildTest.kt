package io.github.jiyimeta.wirelet.gradle

import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class IncrementalRebuildTest {
    @Test
    fun secondInvocationIsUpToDate(
        @TempDir tempDir: File,
    ) {
        setupFixture(tempDir)

        val first = runner(tempDir, "generateWireletCodecsMain").build()
        assertEquals(
            TaskOutcome.SUCCESS,
            first.task(":generateWireletCodecsMain")?.outcome,
        )

        val second = runner(tempDir, "generateWireletCodecsMain").build()
        assertEquals(
            TaskOutcome.UP_TO_DATE,
            second.task(":generateWireletCodecsMain")?.outcome,
            "expected UP-TO-DATE on second invocation",
        )
    }

    @Test
    fun rerunsWhenSchemaChanges(
        @TempDir tempDir: File,
    ) {
        setupFixture(tempDir)
        runner(tempDir, "generateWireletCodecsMain").build()

        // Touch the schema file with a meaningful change.
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
                    public var label: String
                    public init(x: Int32, y: Int32, label: String) {
                        self.x = x
                        self.y = y
                        self.label = label
                    }
                }
                """.trimIndent(),
        )

        val rerun = runner(tempDir, "generateWireletCodecsMain").build()
        assertEquals(
            TaskOutcome.SUCCESS,
            rerun.task(":generateWireletCodecsMain")?.outcome,
            "task should have re-run after schema mutation",
        )
        val regenerated =
            tempDir.resolve(
                "build/generated/wirelet/main/kotlin/com/example/fixture/codec/PointCodec.kt",
            ).readText()
        assertTrue(
            regenerated.contains("label"),
            "regenerated codec missing the new `label` field reference",
        )
    }

    private fun setupFixture(tempDir: File) {
        layoutFixture(
            dir = tempDir,
            extraBuildScript =
                """
                wirelet {
                    swiftPackagePath.set(file(${'"'}${wireletRepoRoot.absolutePath}${'"'}))
                    sources.register("main") {
                        schemaPaths.from(file("schema"))
                        codecPackage.set("com.example.fixture.codec")
                        modelPackage.set("com.example.fixture.model")
                    }
                }
                tasks.named("compileKotlin") { enabled = false }
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
    }
}
