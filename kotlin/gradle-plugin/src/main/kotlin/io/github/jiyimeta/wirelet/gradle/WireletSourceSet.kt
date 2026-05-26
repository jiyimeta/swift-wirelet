package io.github.jiyimeta.wirelet.gradle

import org.gradle.api.Named
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.provider.Property
import org.gradle.api.provider.SetProperty
import javax.inject.Inject

/**
 * One generation source set declared inside the `wirelet { sources { ... } }`
 * container. Each source set produces a single `GenerateWireletCodecs<Name>`
 * task that runs the `emit-wirelet-kotlin` CLI against `schemaPaths` and
 * writes generated Kotlin into `${buildDir}/generated/wirelet/<name>/kotlin`.
 *
 * v1 limitation: `schemaPaths` must resolve to exactly one directory. The
 * underlying CLI accepts a single `--source` argument; multi-path support
 * is a deferred CLI change.
 */
abstract class WireletSourceSet @Inject constructor(private val sourceSetName: String) : Named {
    override fun getName(): String = sourceSetName

    /**
     * Directories scanned for `@WireFormat` / `@WireFormatChoice` /
     * `@WireFormatEnum` Swift declarations. v1: exactly one entry.
     */
    abstract val schemaPaths: ConfigurableFileCollection

    /** Kotlin package the generated `*Codec.kt` files land under. Required. */
    abstract val codecPackage: Property<String>

    /**
     * Kotlin package the model data classes live under. Defaults to
     * `codecPackage` when unset. Only meaningful when `emitModels` is true
     * or the consumer hand-authors models under this package.
     */
    abstract val modelPackage: Property<String>

    /**
     * Kotlin package containing `BinaryReader` / `BinaryWriter`. Defaults to
     * `io.github.jiyimeta.wirelet` (the runtime artifact's package).
     */
    abstract val serializationPackage: Property<String>

    /**
     * Filter: when non-empty, only codecs whose resolved Kotlin package
     * exactly matches one of these entries are written. Mirrors the
     * `--include-package` CLI flag.
     */
    abstract val includePackages: SetProperty<String>

    /**
     * When true the plugin also emits `data class` / `sealed class` /
     * `enum class` model declarations into `modelPackage`. Default false.
     */
    abstract val emitModels: Property<Boolean>

    /**
     * Optional Kotlin name suffix to strip from each generated type's name.
     * Set to e.g. `"Wire"` to turn `PointWire` (Swift) into `Point` (Kotlin).
     */
    abstract val stripNameSuffix: Property<String>
}
