import Foundation
import PackagePlugin

/// SwiftPM build tool plugin that generates `@_cdecl` JNI bridge functions
/// for every `@WireletObservable @Observable final class` found in the target.
///
/// Uses a `.buildCommand` (not `.prebuildCommand`) so the executable tool can
/// be built from source. Output file names are pre-computed by scanning source
/// files for `@WireletObservable` class declarations — one output file per
/// matching class (`<ClassName>+JNIBridges.swift`).
@main
struct WireletObservableBridgesPlugin: BuildToolPlugin {
    func createBuildCommands(
        context: PluginContext,
        target: any Target
    ) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else { return [] }
        let cli = try context.tool(named: "EmitWireletObservableSwiftBridges")
        let outputDirURL = context.pluginWorkDirectoryURL.appending(
            path: "GeneratedBridges",
            directoryHint: .isDirectory
        )
        // Pre-compute output file names by scanning source files for
        // @WireletObservable class declarations. This is intentionally
        // simple — just a text scan for the attribute+class pattern.
        let swiftFiles = sourceTarget.sourceFiles(withSuffix: ".swift")
        var classNames: [String] = []
        for file in swiftFiles {
            guard let source = try? String(contentsOf: file.url, encoding: .utf8) else {
                continue
            }
            classNames.append(contentsOf: extractObservableClassNames(from: source))
        }
        let outputFiles = classNames.map { name in
            outputDirURL.appending(path: "\(name)+JNIBridges.swift")
        }
        return [
            .buildCommand(
                displayName: "Generating WireletObservable JNI bridges for \(target.name)",
                executable: cli.url,
                arguments: [
                    "--source", sourceTarget.directory.string,
                    "--output", outputDirURL.path(percentEncoded: false),
                ],
                inputFiles: swiftFiles.map(\.url),
                outputFiles: outputFiles
            ),
        ]
    }

    // MARK: - Simple text scanner

    /// Scans Swift source text for classes annotated with `@WireletObservable`.
    /// Returns the class names found. This is a text-level heuristic — not a
    /// full parser — sufficient for the plugin's output-file pre-declaration.
    private func extractObservableClassNames(from source: String) -> [String] {
        var names: [String] = []
        let lines = source.components(separatedBy: .newlines)
        var seenObservable = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("@WireletObservable") {
                seenObservable = true
                continue
            }
            if seenObservable {
                if trimmed.contains("@Observable") || trimmed.contains("@_Observable") {
                    // Skip — still in the attribute block
                    continue
                }
                // Look for a class declaration
                if let match = classNameFromLine(trimmed) {
                    names.append(match)
                    seenObservable = false
                } else if trimmed.hasPrefix("@") {
                    // Another attribute — keep scanning
                    continue
                } else {
                    // Something unexpected — reset
                    seenObservable = false
                }
            }
        }
        return names
    }

    private func classNameFromLine(_ line: String) -> String? {
        // Match: [modifiers] class <Name> [: ...] [{]
        // e.g. "public final class CounterVM {" or "final class CounterVM:"
        let words = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard let classIdx = words.firstIndex(of: "class"), classIdx + 1 < words.count else {
            return nil
        }
        var name = words[classIdx + 1]
        // Strip trailing punctuation (:, {)
        name = name.components(separatedBy: CharacterSet(charactersIn: ":{<")).first ?? name
        guard !name.isEmpty, name.first?.isLetter == true || name.first == "_" else {
            return nil
        }
        return name
    }
}
