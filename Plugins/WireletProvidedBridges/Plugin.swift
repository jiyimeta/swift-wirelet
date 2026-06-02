import Foundation
import PackagePlugin

/// SwiftPM build tool plugin that generates `<Service>WireletProxy` proxy classes
/// for every `@WireletProvided` protocol found in the target.
///
/// Uses a `.buildCommand` (not `.prebuildCommand`) so the executable tool can
/// be built from source. Output file names are pre-computed by scanning source
/// files for `@WireletProvided` protocol declarations — one output file per
/// matching protocol (`<ProtocolName>+WireletProxy.swift`).
///
/// Unlike the observable plugin, there is no sidecar input — the provided
/// proxy has no JNI_OnLoad requirement, so no `.wirelet-provided-*.json` file
/// is expected or tracked.
@main
struct WireletProvidedBridgesPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: any Target
    ) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else { return [] }
        let cli = try context.tool(named: "EmitWireletProvidedSwiftBridges")
        let outputDirURL = context.pluginWorkDirectoryURL.appending(
            path: "GeneratedProxies",
            directoryHint: .isDirectory
        )
        // Pre-compute output file names by scanning source files for
        // @WireletProvided protocol declarations. This is intentionally
        // simple — just a text scan for the attribute+protocol pattern.
        let swiftFiles = sourceTarget.sourceFiles(withSuffix: ".swift")
        var protocolNames: [String] = []
        for file in swiftFiles {
            guard let source = try? String(contentsOf: file.url, encoding: .utf8) else {
                continue
            }
            protocolNames.append(contentsOf: extractProvidedProtocolNames(from: source))
        }
        let outputFiles = protocolNames.map { name in
            outputDirURL.appending(path: "\(name)+WireletProxy.swift")
        }

        let arguments: [String] = [
            "--source", sourceTarget.directory.string,
            "--output", outputDirURL.path(percentEncoded: false),
        ]
        let inputFiles = swiftFiles.map(\.url)

        return [
            .buildCommand(
                displayName: "Generating WireletProvided proxies for \(target.name)",
                executable: cli.url,
                arguments: arguments,
                inputFiles: inputFiles,
                outputFiles: outputFiles
            ),
        ]
    }

    // MARK: - Simple text scanner

    /// Scans Swift source text for protocols annotated with `@WireletProvided`.
    /// Returns the protocol names found. This is a text-level heuristic — not a
    /// full parser — sufficient for the plugin's output-file pre-declaration.
    private func extractProvidedProtocolNames(from source: String) -> [String] {
        var names: [String] = []
        let lines = source.components(separatedBy: .newlines)
        var seenProvided = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("@WireletProvided") {
                seenProvided = true
                continue
            }
            if seenProvided {
                // Look for a protocol declaration
                if let match = protocolNameFromLine(trimmed) {
                    names.append(match)
                    seenProvided = false
                } else if trimmed.hasPrefix("@") {
                    // Another attribute — keep scanning
                    continue
                } else {
                    // Something unexpected — reset
                    seenProvided = false
                }
            }
        }
        return names
    }

    private func protocolNameFromLine(_ line: String) -> String? {
        // Match: [modifiers] protocol <Name> [: ...] [{]
        // e.g. "public protocol TodoStore {" or "protocol TodoStore:"
        let words = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let protocolIdx = words.firstIndex(of: "protocol"), protocolIdx + 1 < words.count else {
            return nil
        }
        var name = words[protocolIdx + 1]
        // Strip trailing punctuation (:, {)
        name = name.components(separatedBy: CharacterSet(charactersIn: ":{<")).first ?? name
        guard !name.isEmpty, name.first?.isLetter == true || name.first == "_" else {
            return nil
        }
        return name
    }
}
