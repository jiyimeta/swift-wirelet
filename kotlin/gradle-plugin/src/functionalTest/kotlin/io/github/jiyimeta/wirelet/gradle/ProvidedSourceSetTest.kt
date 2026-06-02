package io.github.jiyimeta.wirelet.gradle

import org.gradle.testkit.runner.TaskOutcome
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.io.File
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class ProvidedSourceSetTest {
    @Test
    fun generatesAdapterKotlinForSimpleTodoStore(@TempDir tempDir: File) {
        layoutFixture(
            dir = tempDir,
            extraBuildScript = """
                wirelet {
                    swiftPackagePath.set(file(${'"'}${wireletRepoRoot.absolutePath}${'"'}))
                    provided {
                        register("main") {
                            schemaPaths.from(file("schema"))
                            interfacePackage.set("com.example.fixture.provided")
                            adapterPackage.set("com.example.fixture.provided")
                            modelPackage.set("com.example.fixture.model")
                            codecPackage.set("com.example.fixture.codec")
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
            relativePath = "schema/TodoStore.swift",
            content = """
                import WireletProvided

                @WireletProvided
                public protocol TodoStore {
                    func remove(_ id: Int32)
                }
            """.trimIndent(),
        )

        val result = runner(tempDir, "generateWireletProvidedInterfacesMain").build()

        assertEquals(
            TaskOutcome.SUCCESS,
            result.task(":generateWireletProvidedInterfacesMain")?.outcome,
            "provided generate task did not run to SUCCESS",
        )
        val expectedFile = tempDir.resolve(
            "build/generated/wirelet/provided/main/kotlin/" +
                "com/example/fixture/provided/TodoStore.kt",
        )
        assertTrue(expectedFile.exists(), "adapter file not written at $expectedFile")
        val content = expectedFile.readText()
        assertTrue(
            content.contains("interface TodoStore"),
            "expected generated interface; got:\n$content",
        )
        assertTrue(
            content.contains("class TodoStoreNativeAdapter"),
            "expected generated adapter class; got:\n$content",
        )
    }
}
