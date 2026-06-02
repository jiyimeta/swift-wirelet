package io.github.jiyimeta.wirelet.gradle

import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.FileTree
import org.gradle.api.provider.Property
import org.gradle.api.provider.SetProperty
import org.gradle.api.tasks.CacheableTask
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputFiles
import org.gradle.api.tasks.Internal
import org.gradle.api.tasks.Optional
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction
import org.gradle.process.ExecOperations
import javax.inject.Inject

/**
 * Generates `<Name>.kt` interface + adapter files for `@WireletProvided`
 * protocol declarations by writing a `provided-codegen.json` config file in
 * the task's temporary directory and forking `swift run --package-path
 * <swiftPackagePath> emit-wirelet-provided --config <json> --source <dir>
 * --output <outputDir>`. Honours `--include-package` filters via the CLI.
 *
 * Marked `@CacheableTask`: outputs are pure functions of inputs (schema
 * sources + CLI source files + config inputs) so build cache works.
 */
@CacheableTask
abstract class GenerateWireletProvidedInterfaces @Inject constructor(
    private val execOperations: ExecOperations,
) : DefaultTask() {

    /**
     * The schema source directories. Declared `@Internal` because tracking
     * the full directory would pick up any non-Swift files in the same tree.
     * The effective Gradle input is [swiftSourceFiles], which filters to
     * `.swift` files only.
     */
    @get:Internal
    abstract val schemaPaths: ConfigurableFileCollection

    /**
     * Swift source files derived from [schemaPaths], filtered to `.swift`
     * only. This is the tracked `@InputFiles` for UP-TO-DATE and build-cache
     * purposes.
     */
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    val swiftSourceFiles: FileTree
        get() = schemaPaths.asFileTree.matching { include("**/*.swift") }

    /**
     * Filesystem location of the wirelet Swift package — used at exec time
     * to fork `swift run --package-path …`. Marked `@Internal` because
     * `swift run` mutates `.build/` / `.swiftpm/` on every invocation,
     * defeating UP-TO-DATE checks. The version-tracked subset is
     * fingerprinted through [cliSourceTree].
     */
    @get:Internal
    abstract val swiftPackagePath: DirectoryProperty

    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    val cliSourceTree: FileTree
        get() = swiftPackagePath.asFileTree.matching {
            include("Sources/**")
            include("Package.swift")
        }

    @get:Input abstract val interfacePackage: Property<String>
    @get:Input abstract val adapterPackage: Property<String>
    @get:Input abstract val modelPackage: Property<String>
    @get:Input abstract val codecPackage: Property<String>
    @get:Input abstract val runtimePackage: Property<String>
    @get:Input abstract val includePackages: SetProperty<String>

    @get:OutputDirectory abstract val outputDir: DirectoryProperty

    @TaskAction
    fun generate() {
        val schemaDir = schemaPaths.files.singleOrNull()
            ?: throw GradleException(
                "wirelet provided: schemaPaths must resolve to exactly one " +
                    "directory (got ${schemaPaths.files.size}). Multi-path " +
                    "support is deferred to a later release."
            )
        if (!schemaDir.isDirectory) {
            throw GradleException(
                "wirelet provided: schemaPaths entry is not a directory: $schemaDir"
            )
        }

        val configFile = temporaryDir.resolve("provided-codegen.json")
        configFile.writeText(buildCodegenConfigJson())

        val out = outputDir.get().asFile
        out.mkdirs()

        val args = mutableListOf(
            "run", "--package-path", swiftPackagePath.get().asFile.absolutePath,
            "emit-wirelet-provided",
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
        val iface = interfacePackage.get()
        val adapter = adapterPackage.get()
        val model = modelPackage.get()
        val codec = codecPackage.get()
        val rt = runtimePackage.get()
        return """
            {
              "interfacePackage": ${quote(iface)},
              "adapterPackage": ${quote(adapter)},
              "modelPackage": ${quote(model)},
              "codecPackage": ${quote(codec)},
              "runtimePackage": ${quote(rt)}
            }
        """.trimIndent()
    }

    private fun quote(s: String): String {
        val escaped = s.replace("\\", "\\\\").replace("\"", "\\\"")
        return "\"$escaped\""
    }
}
