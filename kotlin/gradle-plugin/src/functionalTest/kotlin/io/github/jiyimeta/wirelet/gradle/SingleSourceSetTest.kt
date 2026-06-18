package io.github.jiyimeta.wirelet.gradle

import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SingleSourceSetTest {
    @Test
    fun generatesCodecsAndProducesKotlinSource(
        @TempDir tempDir: File,
    ) {
        layoutFixture(
            dir = tempDir,
            extraBuildScript =
                """
                dependencies {
                    implementation("io.github.jiyimeta:wirelet-runtime:0.0.0-SNAPSHOT")
                }
                wirelet {
                    swiftPackagePath.set(file(${'"'}${wireletRepoRoot.absolutePath}${'"'}))
                    sources.register("main") {
                        schemaPaths.from(file("schema"))
                        codecPackage.set("com.example.fixture.codec")
                        modelPackage.set("com.example.fixture.model")
                    }
                }
                // Avoid resolving the runtime artifact (not published yet);
                // we only care that the generate task itself succeeds.
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

        val result = runner(tempDir, "generateWireletCodecsMain").build()

        assertEquals(
            TaskOutcome.SUCCESS,
            result.task(":generateWireletCodecsMain")?.outcome,
            "generate task did not run to SUCCESS",
        )
        val expectedCodec =
            tempDir.resolve(
                "build/generated/wirelet/main/kotlin/com/example/fixture/codec/PointCodec.kt",
            )
        assertTrue(expectedCodec.exists(), "codec file not written at $expectedCodec")
        val content = expectedCodec.readText()
        assertTrue(
            content.contains("public object PointCodec"),
            "expected generated codec object; got:\n$content",
        )
    }
}
