package io.github.jiyimeta.wirelet.gradle

import org.gradle.api.Named
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.provider.Property
import org.gradle.api.provider.SetProperty
import javax.inject.Inject

/**
 * One provided-codegen source set declared inside the
 * `wirelet { provided { ... } }` container. Each source set produces a
 * single `GenerateWireletProvidedInterfaces<Name>` task that runs the
 * `emit-wirelet-provided` CLI against `schemaPaths` and writes generated
 * `<Name>.kt` (interface + adapter) into
 * `${buildDir}/generated/wirelet/provided/<name>/kotlin`.
 *
 * v1 limitation: `schemaPaths` must resolve to exactly one directory — the
 * underlying CLI takes a single `--source` argument.
 */
abstract class WireletProvidedSourceSet
    @Inject
    constructor(
        private val sourceSetName: String,
    ) : Named {
        override fun getName(): String = sourceSetName

        /**
         * Directories scanned for `@WireletProvided` Swift protocol declarations.
         * v1: exactly one entry.
         */
        abstract val schemaPaths: ConfigurableFileCollection

        /**
         * Kotlin package the generated `<Name>.kt` interface + adapter files land
         * under. Required.
         */
        abstract val interfacePackage: Property<String>

        /**
         * Kotlin package the adapter class would land in for a future split-file
         * layout. Currently colocated with the interface in v1, but kept in config
         * for forward-compatibility. Required.
         */
        abstract val adapterPackage: Property<String>

        /**
         * Kotlin package the user-authored model classes (`TodoItem`, etc.) live
         * in. Required when any service method uses `@WireFormat` struct types.
         */
        abstract val modelPackage: Property<String>

        /**
         * Kotlin package containing the per-`@WireFormat` codec objects.
         * Required when any service method uses `@WireFormat` struct types.
         */
        abstract val codecPackage: Property<String>

        /**
         * Kotlin package containing `WireletList` and any future runtime helpers.
         * Defaults to `io.github.jiyimeta.wirelet.observable` — the package that
         * wirelet-observable-runtime publishes under.
         */
        abstract val runtimePackage: Property<String>

        /**
         * Filter: when non-empty, only interfaces whose resolved Kotlin package
         * exactly matches one of these entries are written. Mirrors the
         * `--include-package` CLI flag.
         */
        abstract val includePackages: SetProperty<String>
    }
