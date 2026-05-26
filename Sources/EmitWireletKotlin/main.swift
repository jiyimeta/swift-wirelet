import Foundation
import WireletKotlinEmitter
import WireletSchema

struct CLIArguments {
    var configPath: String
    var sourceDir: String
    var outputDir: String
    /// When non-empty, only codecs whose Kotlin package exactly matches one of
    /// these entries are written. Lets a multi-module Gradle build invoke the
    /// same generator once per module, with each module owning a disjoint set
    /// of packages — replacing the older "emit everything then exclude in
    /// Kotlin compile" workaround.
    var includePackages: Set<String>

    static func parse(_ argv: [String]) -> CLIArguments? {
        var config: String?
        var source: String?
        var output: String?
        var includePackages = Set<String>()
        var i = 1
        while i < argv.count {
            let key = argv[i]
            switch key {
            case "--config": config = argv[safe: i + 1]; i += 2
            case "--source": source = argv[safe: i + 1]; i += 2
            case "--output": output = argv[safe: i + 1]; i += 2
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
        )
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Stderr write that doesn't touch the global `stderr` var (which Swift 6.1's
/// strict-concurrency check rejects as not Sendable). `FileHandle.standardError`
/// is the platform-stable replacement and is concurrency-safe.
private func writeStderr(_ s: String) {
    FileHandle.standardError.write(Data(s.utf8))
}

guard let args = CLIArguments.parse(CommandLine.arguments) else {
    writeStderr("""
    usage: emit-wirelet-kotlin --config <file> --source <dir> --output <dir> \
    [--include-package <name>]...
    """)
    exit(2)
}

let configURL = URL(fileURLWithPath: args.configPath)
let configData = try Data(contentsOf: configURL)
let config = try JSONDecoder().decode(KotlinCodegenConfig.self, from: configData)

let sourceURL = URL(fileURLWithPath: args.sourceDir, isDirectory: true)
var aggregateSchema = Schema(types: [])
if let enumerator = FileManager.default.enumerator(
    at: sourceURL,
    includingPropertiesForKeys: [.isRegularFileKey],
) {
    for case let url as URL in enumerator {
        guard url.pathExtension == "swift" else { continue }
        let source = try String(contentsOf: url, encoding: .utf8)
        let schema = SchemaParser.parse(source: source, fileName: url.lastPathComponent)
        aggregateSchema.types.append(contentsOf: schema.types)
    }
}

let emitter = KotlinEmitter(config: config)
let allFiles = try emitter.emit(schema: aggregateSchema)

/// Derives the Kotlin package from a file's relativePath
/// (e.g. `com/example/foo/MyCodec.kt` →
/// `com.example.foo`).
func kotlinPackage(of relativePath: String) -> String {
    let dir = (relativePath as NSString).deletingLastPathComponent
    return dir.replacingOccurrences(of: "/", with: ".")
}

let files: [KotlinFile] = args.includePackages.isEmpty
    ? allFiles
    : allFiles.filter { args.includePackages.contains(kotlinPackage(of: $0.relativePath)) }

let outputURL = URL(fileURLWithPath: args.outputDir, isDirectory: true)

/// Track generated files so we can prune deletions. Paths are
/// canonicalised via `resolvingSymlinksInPath()` before insertion / lookup
/// because `FileManager.enumerator` returns symlink-resolved paths
/// (e.g. `/tmp/foo` is reported as `/private/tmp/foo` on macOS, which
/// firmlinks `/tmp` to `/private/tmp`). Without canonicalisation the sweep
/// below would always miss its own freshly-written files and delete them.
var generatedPaths = Set<String>()
for file in files {
    let dest = outputURL.appendingPathComponent(file.relativePath)
    try FileManager.default.createDirectory(
        at: dest.deletingLastPathComponent(),
        withIntermediateDirectories: true,
    )
    if let existing = try? String(contentsOf: dest, encoding: .utf8), existing == file.content {
        // Idempotent: skip rewriting unchanged file (preserves mtime).
    } else {
        try file.content.write(to: dest, atomically: true, encoding: .utf8)
    }
    generatedPaths.insert(dest.resolvingSymlinksInPath().path)
}

// Sweep stale files: any .kt under outputDir that we didn't write this run.
if let sweep = FileManager.default.enumerator(at: outputURL, includingPropertiesForKeys: nil) {
    for case let url as URL in sweep {
        let resolved = url.resolvingSymlinksInPath().path
        guard url.pathExtension == "kt", !generatedPaths.contains(resolved) else { continue }
        try? FileManager.default.removeItem(at: url)
    }
}
