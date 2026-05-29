package io.github.jiyimeta.wirelet.gradle

import org.gradle.api.Action
import org.gradle.api.NamedDomainObjectContainer
import org.gradle.api.file.DirectoryProperty

/**
 * Top-level `wirelet { ... }` DSL extension. The named `sources` container
 * holds one entry per Kotlin source set the plugin should feed; the plugin
 * creates one generate task per entry.
 *
 * `swiftPackagePath` points at the consumer's local wirelet repo checkout.
 * The plugin invokes the bundled CLI via
 * `swift run --package-path <swiftPackagePath> emit-wirelet-kotlin ...`,
 * so a Swift toolchain on the host is required. There is no fallback to a
 * pre-built binary in v1.
 */
abstract class WireletExtension {
    /** Path to a local wirelet repo checkout. Required. */
    abstract val swiftPackagePath: DirectoryProperty

    /** Generation source sets keyed by name. */
    abstract val sources: NamedDomainObjectContainer<WireletSourceSet>

    /** Configure-by-name shorthand for `sources { ... }`. */
    fun sources(configure: Action<NamedDomainObjectContainer<WireletSourceSet>>) {
        configure.execute(sources)
    }

    /** Generation source sets for `@WireletObservable` view-models. */
    abstract val observable: NamedDomainObjectContainer<WireletObservableSourceSet>

    /** Configure-by-name shorthand for `observable { ... }`. */
    fun observable(configure: Action<NamedDomainObjectContainer<WireletObservableSourceSet>>) {
        configure.execute(observable)
    }
}
