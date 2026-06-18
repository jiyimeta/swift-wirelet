import Foundation
import WireletKotlinEmitter
import WireletObservableKotlinEmitter
import WireletObservableSchema

struct CLIArguments {
    var configPath: String
    var sourceDir: String
    var outputDir: String
    /// Same semantics as `emit-wirelet-kotlin --include-package` —
    /// filters generated files by the Kotlin package of their relative
    /// path. Multi-module Gradle builds use this to assign disjoint
    /// view-model packages to disjoint modules from one schema source.
    var includePackages: Set<String>
    /// Optional path for the `.wirelet-observable-jni.json` sidecar. When
    /// present, `emit-wirelet-observable` writes JNI registration metadata
    /// alongside the Kotlin output so the `WireletObservableBridges` SwiftPM
    /// build tool plugin can emit a matching `JNI_OnLoad`.
    var jniSidecarPath: String?

    static func parse(_ argv: [String]) -> CLIArguments? {
        var config: String?
        var source: String?
        var output: String?
        var jniSidecar: String?
        var includePackages = Set<String>()
        var i = 1
        while i < argv.count {
            let key = argv[i]
            switch key {
            case "--config": config = argv[safe: i + 1]; i += 2
            case "--source": source = argv[safe: i + 1]; i += 2
            case "--output": output = argv[safe: i + 1]; i += 2
            case "--jni-sidecar": jniSidecar = argv[safe: i + 1]; i += 2
            case "--include-package":
                if let pkg = argv[safe: i + 1] { includePackages.insert(pkg) }
                i += 2
            default:
                writeStderr("Unknown argument: \(key)\n")
                return nil
            }
        }
        guard let c = config, let s = source, let o = output else { return nil }
        return CLIArguments(
            configPath: c,
            sourceDir: s,
            outputDir: o,
            includePackages: includePackages,
            jniSidecarPath: jniSidecar,
        )
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private func writeStderr(_ s: String) {
    FileHandle.standardError.write(Data(s.utf8))
}

guard let args = CLIArguments.parse(CommandLine.arguments) else {
    writeStderr("""
    usage: emit-wirelet-observable --config <file> --source <dir> --output <dir> \
    [--include-package <name>]... [--jni-sidecar <file>]
    """)
    exit(2)
}

let configURL = URL(fileURLWithPath: args.configPath)
let configData = try Data(contentsOf: configURL)
let config = try JSONDecoder().decode(ObservableCodegenConfig.self, from: configData)

let sourceURL = URL(fileURLWithPath: args.sourceDir, isDirectory: true)
var aggregateSchema = ObservableSchema(viewModels: [])
if let enumerator = FileManager.default.enumerator(
    at: sourceURL,
    includingPropertiesForKeys: [.isRegularFileKey],
) {
    for case let url as URL in enumerator {
        guard url.pathExtension == "swift" else { continue }
        let source = try String(contentsOf: url, encoding: .utf8)
        let schema = ObservableSchemaParser.parse(source: source, fileName: url.lastPathComponent)
        aggregateSchema.viewModels.append(contentsOf: schema.viewModels)
    }
}

aggregateSchema.viewModels.sort(by: { $0.name < $1.name })

let emitter = ObservableKotlinEmitter(config: config)
let allFiles = emitter.emit(schema: aggregateSchema)

func kotlinPackage(of relativePath: String) -> String {
    let dir = (relativePath as NSString).deletingLastPathComponent
    return dir.replacingOccurrences(of: "/", with: ".")
}

let files: [KotlinFile] = args.includePackages.isEmpty
    ? allFiles
    : allFiles.filter { args.includePackages.contains(kotlinPackage(of: $0.relativePath)) }

let outputURL = URL(fileURLWithPath: args.outputDir, isDirectory: true)

var generatedPaths = Set<String>()
for file in files {
    let dest = outputURL.appendingPathComponent(file.relativePath)
    try FileManager.default.createDirectory(
        at: dest.deletingLastPathComponent(),
        withIntermediateDirectories: true,
    )
    if let existing = try? String(contentsOf: dest, encoding: .utf8), existing == file.content {
        // Idempotent — skip rewrite.
    } else {
        try file.content.write(to: dest, atomically: true, encoding: .utf8)
    }
    generatedPaths.insert(dest.resolvingSymlinksInPath().path)
}

if let sweep = FileManager.default.enumerator(at: outputURL, includingPropertiesForKeys: nil) {
    for case let url as URL in sweep {
        let resolved = url.resolvingSymlinksInPath().path
        guard url.pathExtension == "kt", !generatedPaths.contains(resolved) else { continue }
        try? FileManager.default.removeItem(at: url)
    }
}

// Write the JNI registration sidecar if requested.
if let sidecarPath = args.jniSidecarPath {
    let sidecar = JNISidecarBuilder.build(schema: aggregateSchema, config: config)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let sidecarData = try encoder.encode(sidecar)
    let sidecarURL = URL(fileURLWithPath: sidecarPath)
    if let existing = try? Data(contentsOf: sidecarURL), existing == sidecarData {
        // Idempotent — skip rewrite.
    } else {
        try sidecarData.write(to: sidecarURL)
    }
}
