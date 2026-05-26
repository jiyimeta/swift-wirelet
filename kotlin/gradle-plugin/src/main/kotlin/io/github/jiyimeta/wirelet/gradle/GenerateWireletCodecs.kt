package io.github.jiyimeta.wirelet.gradle

import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.provider.Property
import org.gradle.api.provider.SetProperty
import org.gradle.api.tasks.CacheableTask
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputDirectory
import org.gradle.api.tasks.InputFiles
import org.gradle.api.tasks.Optional
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction
import org.gradle.process.ExecOperations
import javax.inject.Inject

/**
 * Generates Kotlin codecs by writing a `codegen-config.json` file in the
 * task's temporary directory and forking `swift run --package-path
 * <swiftPackagePath> emit-wirelet-kotlin --config <json> --source <dir>
 * --output <outputDir>`. Honours `--include-package` filters via the CLI.
 *
 * Marked `@CacheableTask`: outputs are pure functions of inputs (schema
 * sources, config, CLI version embedded in `swiftPackagePath`) so build
 * cache works.
 */
@CacheableTask
abstract class GenerateWireletCodecs @Inject constructor(
    private val execOperations: ExecOperations,
) : DefaultTask() {

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val schemaPaths: ConfigurableFileCollection

    @get:InputDirectory
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val swiftPackagePath: DirectoryProperty

    @get:Input abstract val codecPackage: Property<String>
    @get:Input abstract val modelPackage: Property<String>
    @get:Input abstract val serializationPackage: Property<String>
    @get:Input abstract val includePackages: SetProperty<String>
    @get:Input abstract val emitModels: Property<Boolean>

    @get:Input
    @get:Optional
    abstract val stripNameSuffix: Property<String>

    @get:OutputDirectory abstract val outputDir: DirectoryProperty

    @TaskAction
    fun generate() {
        val schemaDir = schemaPaths.files.singleOrNull()
            ?: throw GradleException(
                "wirelet: schemaPaths must resolve to exactly one directory " +
                    "(got ${schemaPaths.files.size}). Multi-path support is " +
                    "deferred to a later release."
            )
        if (!schemaDir.isDirectory) {
            throw GradleException(
                "wirelet: schemaPaths entry is not a directory: $schemaDir"
            )
        }

        val configFile = temporaryDir.resolve("codegen-config.json")
        configFile.writeText(buildCodegenConfigJson())

        val out = outputDir.get().asFile
        out.mkdirs()

        val args = mutableListOf(
            "run", "--package-path", swiftPackagePath.get().asFile.absolutePath,
            "emit-wirelet-kotlin",
            "--config", configFile.absolutePath,
            "--source", schemaDir.absolutePath,
            "--output", out.absolutePath,
        )
        for (pkg in includePackages.get()) {
            args += "--include-package"
            args += pkg
        }

        execOperations.exec {
            commandLine("swift", *args.toTypedArray())
        }
    }

    private fun buildCodegenConfigJson(): String {
        val codec = codecPackage.get()
        val model = modelPackage.getOrElse(codec)
        val ser = serializationPackage.get()
        val emit = emitModels.getOrElse(false)
        val suffix = stripNameSuffix.orNull
        val nameTransform = if (suffix.isNullOrEmpty()) {
            """{ "identity": true }"""
        } else {
            """{ "stripSuffix": ${quote(suffix)} }"""
        }
        return """
            {
              "defaultModelPackage": ${quote(model)},
              "defaultCodecPackage": ${quote(codec)},
              "defaultSerializationPackage": ${quote(ser)},
              "nameTransform": $nameTransform,
              "rules": [],
              "emitModels": $emit
            }
        """.trimIndent()
    }

    private fun quote(s: String): String {
        val escaped = s.replace("\\", "\\\\").replace("\"", "\\\"")
        return "\"$escaped\""
    }
}
