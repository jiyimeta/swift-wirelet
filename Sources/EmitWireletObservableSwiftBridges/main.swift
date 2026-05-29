import Foundation
import WireletObservableSwiftBridgesEmitter

// MARK: - CLI argument parsing

struct CLIArguments {
    var sourceDir: String
    var outputDir: String
    /// Optional path to the `.wirelet-observable-jni.json` sidecar file.
    /// When present, the emitter appends a consolidated `JNI_OnLoad` file.
    var jniConfigPath: String?

    static func parse(_ argv: [String]) -> CLIArguments? {
        var source: String?
        var output: String?
        var jniConfig: String?
        var i = 1
        while i < argv.count {
            let key = argv[i]
            switch key {
            case "--source": source = argv[safe: i + 1]; i += 2
            case "--output": output = argv[safe: i + 1]; i += 2
            case "--jni-config": jniConfig = argv[safe: i + 1]; i += 2
            default:
                writeStderr("Unknown argument: \(key)\n")
                return nil
            }
        }
        guard let s = source, let o = output else { return nil }
        return CLIArguments(sourceDir: s, outputDir: o, jniConfigPath: jniConfig)
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

// MARK: - Entry point

guard let args = CLIArguments.parse(CommandLine.arguments) else {
    writeStderr("usage: emit-wirelet-observable-swift-bridges --source <dir> --output <dir> [--jni-config <file>]\n")
    exit(2)
}

let sourceURL = URL(fileURLWithPath: args.sourceDir, isDirectory: true)
let outputURL = URL(fileURLWithPath: args.outputDir, isDirectory: true)

// Collect all .swift files under the source directory.
var swiftFiles: [URL] = []
if let enumerator = FileManager.default.enumerator(
    at: sourceURL,
    includingPropertiesForKeys: [.isRegularFileKey]
) {
    for case let url as URL in enumerator {
        guard url.pathExtension == "swift" else { continue }
        swiftFiles.append(url)
    }
}

// Load optional JNI registration sidecar.
var jniConfig: JNIRegistrationConfig?
if let jniConfigPath = args.jniConfigPath {
    let jniConfigURL = URL(fileURLWithPath: jniConfigPath)
    let jniData = try Data(contentsOf: jniConfigURL)
    jniConfig = try JSONDecoder().decode(JNIRegistrationConfig.self, from: jniData)
}

let emitter = SwiftBridgesEmitter()
let outputs = try emitter.emit(sources: swiftFiles, jniConfig: jniConfig)

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

for (name, content) in outputs {
    let dest = outputURL.appendingPathComponent(name)
    if let existing = try? String(contentsOf: dest, encoding: .utf8), existing == content {
        // Idempotent: skip rewriting unchanged file (preserves mtime for incremental builds).
    } else {
        try content.write(to: dest, atomically: true, encoding: .utf8)
    }
}
