import Foundation
import PackagePlugin

/// SwiftPM build tool plugin that generates `@_cdecl` JNI bridge functions
/// for every `@WireletObservable @Observable final class` found in the target.
///
/// The plugin invokes the `emit-wirelet-observable-swift-bridges` CLI as a
/// pre-build command (outputs are not declared up-front because the class
/// names — and therefore file names — are not known until the CLI runs).
/// SwiftPM pre-build commands run before compilation and their output
/// directory is automatically added to the target's source search path.
@main
struct WireletObservableBridgesPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: any Target
    ) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else { return [] }
        let cli = try context.tool(named: "emit-wirelet-observable-swift-bridges")
        let outputDirURL = context.pluginWorkDirectoryURL.appending(
            path: "GeneratedBridges",
            directoryHint: .isDirectory
        )
        return [
            .prebuildCommand(
                displayName: "Generating WireletObservable JNI bridges for \(target.name)",
                executable: cli.url,
                arguments: [
                    "--source", sourceTarget.directory.string,
                    "--output", outputDirURL.path(percentEncoded: false),
                ],
                outputFilesDirectory: outputDirURL
            ),
        ]
    }
}
