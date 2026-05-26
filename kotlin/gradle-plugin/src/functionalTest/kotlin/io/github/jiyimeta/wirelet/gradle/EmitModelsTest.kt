package io.github.jiyimeta.wirelet.gradle

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertTrue

class EmitModelsTest {
    @Test
    fun emitModelsTrueGeneratesDataClass(@TempDir tempDir: File) {
        layoutFixture(
            dir = tempDir,
            extraBuildScript = """
                wirelet {
                    swiftPackagePath.set(file("${wireletRepoRoot.absolutePath}"))
                    sources.register("main") {
                        schemaPaths.from(file("schema"))
                        codecPackage.set("com.example.fixture.codec")
                        modelPackage.set("com.example.fixture.model")
                        emitModels.set(true)
                    }
                }
                tasks.named("compileKotlin") { enabled = false }
            """.trimIndent(),
        )
        writeSchemaFile(
            dir = tempDir,
            relativePath = "schema/Point.swift",
            content = """
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

        runner(tempDir, "generateWireletCodecsMain").build()

        val model = tempDir.resolve(
            "build/generated/wirelet/main/kotlin/com/example/fixture/model/Point.kt",
        )
        assertTrue(model.exists(), "model file not generated at $model")
        val content = model.readText()
        assertTrue(content.contains("public data class Point("), "expected `data class Point(`; got:\n$content")
        assertTrue(content.contains("val x: Int"), "missing field x")
        assertTrue(content.contains("val y: Int"), "missing field y")
    }
}
