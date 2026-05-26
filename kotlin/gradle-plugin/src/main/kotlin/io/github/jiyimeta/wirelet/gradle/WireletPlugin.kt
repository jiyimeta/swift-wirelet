package io.github.jiyimeta.wirelet.gradle

import org.gradle.api.Plugin
import org.gradle.api.Project
import org.gradle.api.file.SourceDirectorySet
import org.gradle.api.tasks.SourceSetContainer

class WireletPlugin : Plugin<Project> {
    override fun apply(target: Project) {
        val extension = target.extensions.create("wirelet", WireletExtension::class.java)
        extension.sources.all { registerSourceSet(target, extension, this) }
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
    }
}
