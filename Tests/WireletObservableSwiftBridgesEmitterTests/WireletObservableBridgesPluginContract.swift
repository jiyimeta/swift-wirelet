import Foundation
import Testing
import WireletObservableSwiftBridgesEmitter

// MARK: - SwiftPM plugin contract regression

/// The `WireletObservableBridges` SwiftPM build tool plugin lives in
/// `Plugins/WireletObservableBridges/Plugin.swift`. Plugin targets cannot
/// depend on library targets, so the plugin code can't be unit-tested
/// directly. This smoke test reads the plugin source as text and asserts
/// the one invariant that, if broken, silently regresses to a known crash
/// (UnsatisfiedLinkError on a freshly-added `@WireletExpose` method after
/// an incremental cross-build). The contract:
///
///   When a `.wirelet-observable-jni.json` sidecar is present, the plugin
///   MUST append its path to `inputFiles` of the build command. Otherwise
///   SwiftPM treats the cached `JNI_OnLoad.swift` as UP-TO-DATE when the
///   sidecar changes, leaving the new method un-registered.
@Suite("WireletObservableBridgesPluginContract")
struct WireletObservableBridgesPluginContract {
    @Test func sidecarIsListedAsBuildCommandInput() throws {
        let pluginURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/WireletObservableSwiftBridgesEmitterTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // swift-wirelet/
            .appendingPathComponent("Plugins/WireletObservableBridges/Plugin.swift")
        let source = try String(contentsOf: pluginURL, encoding: .utf8)
        #expect(
            source.contains("inputFiles.append(URL(fileURLWithPath: sidecarPath))"),
            """
            Plugin.swift must append the sidecar path to inputFiles inside the
            `if FileManager.default.fileExists(atPath: sidecarPath)` block.
            Removing this line silently re-introduces the UnsatisfiedLinkError
            regression when a consumer adds a new @WireletExpose method
            mid-development. See the fix commit + spec compute docs.
            """,
        )
    }
}
