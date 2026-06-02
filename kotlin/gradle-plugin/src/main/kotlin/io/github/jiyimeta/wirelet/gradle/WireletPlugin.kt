package io.github.jiyimeta.wirelet.gradle

import com.android.build.api.variant.AndroidComponentsExtension
import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.file.Directory
import org.gradle.api.file.SourceDirectorySet
import org.gradle.api.provider.Provider
import org.gradle.api.tasks.SourceSetContainer
import org.gradle.api.tasks.TaskProvider

class WireletPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        val extension = target.extensions.create("wirelet", WireletExtension::class.java)
        extension.sources.all { registerSourceSet(target, extension, this) }
        extension.observable.all { registerObservableSourceSet(target, extension, this) }
        extension.provided.all { registerProvidedSourceSet(target, extension, this) }
    }

    private fun registerObservableSourceSet(
        project: Project,
        extension: WireletExtension,
        entry: WireletObservableSourceSet,
    ) {
        val taskName = "generateWireletObservableViewModels${
            entry.name.replaceFirstChar { it.uppercaseChar() }
        }"
        val task = project.tasks.register(
            taskName,
            GenerateWireletObservableViewModels::class.java,
        ) {
            group = "wirelet"
            description = "Generates @WireletObservable view-models for source set '${entry.name}'."
            schemaPaths.from(entry.schemaPaths)
            swiftPackagePath.set(extension.swiftPackagePath)
            viewModelPackage.set(entry.viewModelPackage)
            modelPackage.set(entry.modelPackage)
            codecPackage.set(entry.codecPackage)
            runtimePackage.set(
                entry.runtimePackage.orElse("io.github.jiyimeta.wirelet.observable"),
            )
            libraryName.set(entry.libraryName)
            includePackages.set(entry.includePackages)
            providedAdapterPackage.set(entry.providedAdapterPackage)
            outputDir.set(
                project.layout.buildDirectory.dir(
                    "generated/wirelet/observable/${entry.name}/kotlin",
                ),
            )
            // Wire the JNI sidecar file into the schema source directory so
            // the WireletObservableBridges SwiftPM plugin can find it adjacent
            // to the Swift schema sources and trigger JNI_OnLoad generation.
            //
            // The sidecar is a separate @OutputFile; sibling tasks that scan
            // the same schema directory won't see it as an input because both
            // GenerateWireletCodecs and this task use swiftSourceFiles
            // (filtered to .swift only) as their tracked @InputFiles.
            jniSidecarFile.set(
                entry.schemaPaths.elements.map { elements ->
                    val schemaFile = elements.singleOrNull()?.asFile
                    if (schemaFile != null) {
                        project.layout.projectDirectory.file(
                            schemaFile.resolve(".wirelet-observable-jni.json").absolutePath
                        )
                    } else {
                        null
                    }
                }
            )
        }

        project.plugins.withId("org.jetbrains.kotlin.jvm") {
            wireOutputIntoKotlinSourceSet(project, entry.name, task)
        }
        // Android consumers don't expose `SourceSetContainer`; their Kotlin
        // source sets come from AGP's Variant API. Register the generated
        // directory via AGP's task-aware API so it's wired with proper
        // task dependencies. Listens for both application + library
        // Android Components extensions.
        wireObservableOutputIntoAndroidVariants(project, entry.name, task)
    }

    private fun wireOutputIntoKotlinSourceSet(
        project: Project,
        sourceSetName: String,
        task: TaskProvider<GenerateWireletObservableViewModels>,
    ) {
        val sourceSets = project.extensions.findByType(SourceSetContainer::class.java)
            ?: return
        val kotlinSourceSet = sourceSets.findByName(sourceSetName) ?: return
        val kotlinDirs = kotlinSourceSet.extensions.findByName("kotlin")
            as? SourceDirectorySet
        kotlinDirs?.srcDir(task.flatMap { it.outputDir })

        val compileTaskName = if (sourceSetName == "main") {
            "compileKotlin"
        } else {
            "compile${sourceSetName.replaceFirstChar { it.uppercaseChar() }}Kotlin"
        }
        project.tasks.matching { it.name == compileTaskName }
            .configureEach { dependsOn(task) }
    }

    private fun registerSourceSet(
        project: Project,
        extension: WireletExtension,
        entry: WireletSourceSet,
    ) {
        val taskName = "generateWireletCodecs${entry.name.replaceFirstChar { it.uppercaseChar() }}"
        val task = project.tasks.register(taskName, GenerateWireletCodecs::class.java) {
            group = "wirelet"
            description = "Generates Kotlin codecs for source set '${entry.name}'."
            schemaPaths.from(entry.schemaPaths)
            swiftPackagePath.set(extension.swiftPackagePath)
            codecPackage.set(entry.codecPackage)
            modelPackage.set(entry.modelPackage)
            serializationPackage.set(
                entry.serializationPackage.orElse("io.github.jiyimeta.wirelet"),
            )
            includePackages.set(entry.includePackages)
            emitModels.set(entry.emitModels.orElse(false))
            stripNameSuffix.set(entry.stripNameSuffix)
            outputDir.set(
                project.layout.buildDirectory.dir("generated/wirelet/${entry.name}/kotlin"),
            )
        }

        project.plugins.withId("org.jetbrains.kotlin.jvm") {
            val sourceSets = project.extensions.getByType(SourceSetContainer::class.java)
            val kotlinSourceSet = sourceSets.findByName(entry.name) ?: return@withId
            val kotlinDirs = kotlinSourceSet.extensions.findByName("kotlin")
                as? SourceDirectorySet
            kotlinDirs?.srcDir(task.flatMap { it.outputDir })

            val compileTaskName = if (entry.name == "main") {
                "compileKotlin"
            } else {
                "compile${entry.name.replaceFirstChar { it.uppercaseChar() }}Kotlin"
            }
            project.tasks.matching { it.name == compileTaskName }
                .configureEach { dependsOn(task) }
        }
        wireCodecsOutputIntoAndroidVariants(project, entry.name, task)
    }

    /**
     * Wire the `outputDir` of an observable view-model generation task
     * into every Android variant's Kotlin source set. AGP's task-aware
     * `addGeneratedSourceDirectory(task, prop)` registers the task as the
     * producer of the directory, so AGP carries the dependency through
     * itself — no manual `dependsOn` and no early `.get()` on the property.
     */
    private fun wireObservableOutputIntoAndroidVariants(
        project: Project,
        sourceSetName: String,
        task: TaskProvider<GenerateWireletObservableViewModels>,
    ) {
        listOf("com.android.application", "com.android.library").forEach { pluginId ->
            project.plugins.withId(pluginId) {
                val ext = project.extensions.findByType(
                    AndroidComponentsExtension::class.java,
                ) ?: return@withId
                ext.onVariants { variant ->
                    if (sourceSetName != "main") return@onVariants
                    // Register the generated dir on BOTH the Kotlin and
                    // Java source-dir sets. AGP exposes the Kotlin slot
                    // (since 7.4) but `compileKotlinAndroid` on AGP 8.x
                    // primarily reads from the Java source dirs for
                    // generated Kotlin too; without `.java?.add(...)` the
                    // Kotlin compile doesn't pick up our outputs.
                    variant.sources.kotlin?.addGeneratedSourceDirectory(
                        task,
                        GenerateWireletObservableViewModels::outputDir,
                    )
                    variant.sources.java?.addGeneratedSourceDirectory(
                        task,
                        GenerateWireletObservableViewModels::outputDir,
                    )
                }
            }
        }
    }

    private fun registerProvidedSourceSet(
        project: Project,
        extension: WireletExtension,
        entry: WireletProvidedSourceSet,
    ) {
        val taskName = "generateWireletProvidedInterfaces${
            entry.name.replaceFirstChar { it.uppercaseChar() }
        }"
        val task = project.tasks.register(
            taskName,
            GenerateWireletProvidedInterfaces::class.java,
        ) {
            group = "wirelet"
            description = "Generates @WireletProvided interface + adapter for source set '${entry.name}'."
            schemaPaths.from(entry.schemaPaths)
            swiftPackagePath.set(extension.swiftPackagePath)
            interfacePackage.set(entry.interfacePackage)
            adapterPackage.set(entry.adapterPackage)
            modelPackage.set(entry.modelPackage)
            codecPackage.set(entry.codecPackage)
            runtimePackage.set(
                entry.runtimePackage.orElse("io.github.jiyimeta.wirelet.observable"),
            )
            includePackages.set(entry.includePackages)
            outputDir.set(
                project.layout.buildDirectory.dir(
                    "generated/wirelet/provided/${entry.name}/kotlin",
                ),
            )
        }

        project.plugins.withId("org.jetbrains.kotlin.jvm") {
            wireProvidedOutputIntoKotlinSourceSet(project, entry.name, task)
        }
        wireProvidedOutputIntoAndroidVariants(project, entry.name, task)
    }

    private fun wireProvidedOutputIntoKotlinSourceSet(
        project: Project,
        sourceSetName: String,
        task: TaskProvider<GenerateWireletProvidedInterfaces>,
    ) {
        val sourceSets = project.extensions.findByType(SourceSetContainer::class.java)
            ?: return
        val kotlinSourceSet = sourceSets.findByName(sourceSetName) ?: return
        val kotlinDirs = kotlinSourceSet.extensions.findByName("kotlin")
            as? SourceDirectorySet
        kotlinDirs?.srcDir(task.flatMap { it.outputDir })

        val compileTaskName = if (sourceSetName == "main") {
            "compileKotlin"
        } else {
            "compile${sourceSetName.replaceFirstChar { it.uppercaseChar() }}Kotlin"
        }
        project.tasks.matching { it.name == compileTaskName }
            .configureEach { dependsOn(task) }
    }

    /**
     * Wire the `outputDir` of a provided interface generation task into every
     * Android variant's Kotlin source set. Mirrors
     * [wireObservableOutputIntoAndroidVariants].
     */
    private fun wireProvidedOutputIntoAndroidVariants(
        project: Project,
        sourceSetName: String,
        task: TaskProvider<GenerateWireletProvidedInterfaces>,
    ) {
        listOf("com.android.application", "com.android.library").forEach { pluginId ->
            project.plugins.withId(pluginId) {
                val ext = project.extensions.findByType(
                    AndroidComponentsExtension::class.java,
                ) ?: return@withId
                ext.onVariants { variant ->
                    if (sourceSetName != "main") return@onVariants
                    variant.sources.kotlin?.addGeneratedSourceDirectory(
                        task,
                        GenerateWireletProvidedInterfaces::outputDir,
                    )
                    variant.sources.java?.addGeneratedSourceDirectory(
                        task,
                        GenerateWireletProvidedInterfaces::outputDir,
                    )
                }
            }
        }
    }

    /** Same shape as the observable wiring above but for codec tasks. */
    private fun wireCodecsOutputIntoAndroidVariants(
        project: Project,
        sourceSetName: String,
        task: TaskProvider<GenerateWireletCodecs>,
    ) {
        listOf("com.android.application", "com.android.library").forEach { pluginId ->
            project.plugins.withId(pluginId) {
                val ext = project.extensions.findByType(
                    AndroidComponentsExtension::class.java,
                ) ?: return@withId
                ext.onVariants { variant ->
                    if (sourceSetName != "main") return@onVariants
                    variant.sources.kotlin?.addGeneratedSourceDirectory(
                        task,
                        GenerateWireletCodecs::outputDir,
                    )
                    variant.sources.java?.addGeneratedSourceDirectory(
                        task,
                        GenerateWireletCodecs::outputDir,
                    )
                }
            }
        }
    }
}
