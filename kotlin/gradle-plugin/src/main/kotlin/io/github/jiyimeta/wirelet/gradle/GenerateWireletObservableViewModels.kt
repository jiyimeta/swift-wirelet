package io.github.jiyimeta.wirelet.gradle

import org.gradle.api.DefaultTask
import org.gradle.api.GradleException
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.file.DirectoryProperty
import org.gradle.api.file.FileTree
import org.gradle.api.file.RegularFileProperty
import org.gradle.api.provider.Property
import org.gradle.api.provider.SetProperty
import org.gradle.api.tasks.CacheableTask
import org.gradle.api.tasks.Input
import org.gradle.api.tasks.InputFiles
import org.gradle.api.tasks.Internal
import org.gradle.api.tasks.Optional
import org.gradle.api.tasks.OutputDirectory
import org.gradle.api.tasks.OutputFile
import org.gradle.api.tasks.PathSensitive
import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.TaskAction
import org.gradle.process.ExecOperations
import javax.inject.Inject

/**
 * Generates `<Name>ViewModel.kt` files for `@WireletObservable` declarations
 * by writing an `observable-codegen.json` config file in the task's
 * temporary directory and forking `swift run --package-path
 * <swiftPackagePath> emit-wirelet-observable --config <json> --source <dir>
 * --output <outputDir>`. Honours `--include-package` filters via the CLI.
 *
 * When [jniSidecarFile] is set the task also passes `--jni-sidecar <path>`
 * to the CLI, which writes a `.wirelet-observable-jni.json` file describing
 * every native method that the generated Kotlin class declares. The
 * `WireletObservableBridges` SwiftPM build tool plugin reads this sidecar
 * to auto-generate the `JNI_OnLoad` registration.
 *
 * Marked `@CacheableTask`: outputs are pure functions of inputs (schema
 * sources + CLI source files + config inputs) so build cache works.
 */
@CacheableTask
abstract class GenerateWireletObservableViewModels @Inject constructor(
    private val execOperations: ExecOperations,
) : DefaultTask() {

    /**
     * The schema source directories. Declared `@Internal` because tracking
     * the full directory would pick up non-Swift sidecar files (e.g.
     * `.wirelet-observable-jni.json`) written by this same task. The
     * effective Gradle input is [swiftSourceFiles], which filters to
     * `.swift` files only.
     */
    @get:Internal
    abstract val schemaPaths: ConfigurableFileCollection

    /**
     * Swift source files derived from [schemaPaths], filtered to `.swift`
     * only. This is the tracked `@InputFiles` for UP-TO-DATE and build-cache
     * purposes, ensuring the JSON sidecar this task writes to the same
     * directory does not trigger spurious re-runs on subsequent builds.
     */
    @get:InputFiles
    @get:PathSensitive(PathSensitivity.RELATIVE)
    val swiftSourceFiles: FileTree
        get() = schemaPaths.asFileTree.matching { include("**/*.swift") }

    /**
     * Filesystem location of the wirelet Swift package — used at exec time
     * to fork `swift run --package-path …`. Marked `@Internal` for the same
     * reason as in `GenerateWireletCodecs`: `swift run` mutates `.build/` /
     * `.swiftpm/` on every invocation, defeating UP-TO-DATE checks. The
     * version-tracked subset is fingerprinted through [cliSourceTree].
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

    @get:Input abstract val viewModelPackage: Property<String>
    @get:Input abstract val modelPackage: Property<String>
    @get:Input abstract val codecPackage: Property<String>
    @get:Input abstract val runtimePackage: Property<String>
    @get:Input abstract val libraryName: Property<String>
    @get:Input abstract val includePackages: SetProperty<String>

    @get:OutputDirectory abstract val outputDir: DirectoryProperty

    /**
     * When set, the task writes a `.wirelet-observable-jni.json` sidecar at
     * this path. The `WireletObservableBridges` SwiftPM build tool plugin
     * looks for this file in the Swift target's source directory and passes
     * it to the Swift bridges emitter CLI so it can emit a `JNI_OnLoad`.
     *
     * Conventionally set to `<schemaDir>/.wirelet-observable-jni.json`
     * by the plugin wiring in [WireletPlugin]. Declared `@OutputFile` so
     * Gradle tracks it for UP-TO-DATE checking and build caching.
     *
     * The sidecar is co-located with the Swift schema sources intentionally:
     * the `WireletObservableBridges` SwiftPM build tool plugin can only
     * inspect the target's `sourceTarget.directory`, and the sidecar must
     * be findable at a predictable path within that tree.
     *
     * To prevent the sidecar from being counted as an input by sibling tasks
     * that also scan the same schema directory, both [GenerateWireletCodecs]
     * and this task use [swiftSourceFiles] (`.swift`-only `FileTree`) as
     * their tracked `@InputFiles` rather than the raw [schemaPaths].
     */
    @get:OutputFile
    @get:Optional
    abstract val jniSidecarFile: RegularFileProperty

    @TaskAction
    fun generate() {
        val schemaDir = schemaPaths.files.singleOrNull()
            ?: throw GradleException(
                "wirelet observable: schemaPaths must resolve to exactly one " +
                    "directory (got ${schemaPaths.files.size}). Multi-path " +
                    "support is deferred to a later release."
            )
        if (!schemaDir.isDirectory) {
            throw GradleException(
                "wirelet observable: schemaPaths entry is not a directory: $schemaDir"
            )
        }

        val configFile = temporaryDir.resolve("observable-codegen.json")
        configFile.writeText(buildCodegenConfigJson())

        val out = outputDir.get().asFile
        out.mkdirs()

        val args = mutableListOf(
            "run", "--package-path", swiftPackagePath.get().asFile.absolutePath,
            "emit-wirelet-observable",
            "--config", configFile.absolutePath,
            "--source", schemaDir.absolutePath,
            "--output", out.absolutePath,
        )
        for (pkg in includePackages.get()) {
            args += "--include-package"
            args += pkg
        }
        jniSidecarFile.orNull?.asFile?.let { sidecar ->
            sidecar.parentFile.mkdirs()
            args += "--jni-sidecar"
            args += sidecar.absolutePath
        }

        execOperations.exec {
            commandLine("swift", *args.toTypedArray())
        }
    }

    private fun buildCodegenConfigJson(): String {
        val vm = viewModelPackage.get()
        val model = modelPackage.get()
        val codec = codecPackage.get()
        val rt = runtimePackage.get()
        val lib = libraryName.get()
        return """
            {
              "viewModelPackage": ${quote(vm)},
              "modelPackage": ${quote(model)},
              "codecPackage": ${quote(codec)},
              "runtimePackage": ${quote(rt)},
              "libraryName": ${quote(lib)},
              "nameTransform": { "identity": true }
            }
        """.trimIndent()
    }

    private fun quote(s: String): String {
        val escaped = s.replace("\\", "\\\\").replace("\"", "\\\"")
        return "\"$escaped\""
    }
}
