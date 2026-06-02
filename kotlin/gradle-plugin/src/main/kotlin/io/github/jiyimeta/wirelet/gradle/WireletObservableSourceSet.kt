package io.github.jiyimeta.wirelet.gradle

import org.gradle.api.Named
import org.gradle.api.file.ConfigurableFileCollection
import org.gradle.api.provider.Property
import org.gradle.api.provider.SetProperty
import javax.inject.Inject

/**
 * One observable-codegen source set declared inside the
 * `wirelet { observable { ... } }` container. Each source set produces a
 * single `GenerateWireletObservableViewModels<Name>` task that runs the
 * `emit-wirelet-observable` CLI against `schemaPaths` and writes generated
 * `<Name>ViewModel.kt` into
 * `${buildDir}/generated/wirelet/observable/<name>/kotlin`.
 *
 * v1 limitation: `schemaPaths` must resolve to exactly one directory — the
 * underlying CLI takes a single `--source` argument.
 */
abstract class WireletObservableSourceSet @Inject constructor(
    private val sourceSetName: String,
) : Named {
    override fun getName(): String = sourceSetName

    /**
     * Directories scanned for `@WireletObservable` + `@Observable` Swift
     * class declarations. v1: exactly one entry.
     */
    abstract val schemaPaths: ConfigurableFileCollection

    /**
     * Kotlin package the generated `<Name>ViewModel.kt` files land under.
     * Required.
     */
    abstract val viewModelPackage: Property<String>

    /**
     * Kotlin package the model data classes live under. Required when any
     * `@WireletObservable` view-model has `@WireFormat` struct properties —
     * the generated view-model imports `<modelPackage>.<Name>` for each.
     */
    abstract val modelPackage: Property<String>

    /**
     * Kotlin package containing the per-`@WireFormat` codec objects.
     * Required when any `@WireletObservable` view-model has `@WireFormat`
     * struct properties — the generated view-model imports
     * `<codecPackage>.<Name>Codec` for each.
     */
    abstract val codecPackage: Property<String>

    /**
     * Kotlin package containing `WireletList` (and any future runtime
     * helpers). Defaults to `io.github.jiyimeta.wirelet.observable` — the
     * package wirelet-observable-runtime publishes under.
     */
    abstract val runtimePackage: Property<String>

    /**
     * Name of the `.so` library the generated companion object loads via
     * `System.loadLibrary(...)`. Required — there is no sensible default
     * because the consumer chooses the JNI library name.
     */
    abstract val libraryName: Property<String>

    /**
     * Filter: when non-empty, only view-models whose resolved Kotlin
     * package exactly matches one of these entries are written. Mirrors
     * the `--include-package` CLI flag.
     */
    abstract val includePackages: SetProperty<String>

    /**
     * Kotlin package the `@WireletProvided` service interfaces and their
     * generated `<Service>NativeAdapter` classes live under. Required when
     * any `@WireletObservable` class has an injected initializer
     * (`init(store: TodoStore)`): the generated view-model factory imports
     * `<providedAdapterPackage>.<Service>` and
     * `<providedAdapterPackage>.<Service>NativeAdapter`, and the JNI sidecar
     * builds the adapter-typed `nativeNew` descriptor from it. Optional —
     * leave unset when no view-model has injected init parameters; the JSON
     * key is then omitted and the codegen config decodes it as nil.
     */
    abstract val providedAdapterPackage: Property<String>
}
