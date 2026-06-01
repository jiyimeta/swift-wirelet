import Foundation
import Testing

@Test func cliEmitsTodoStoreAdapter() throws {
    let fixturesDir = try #require(
        Bundle.module.resourceURL?.appendingPathComponent("Fixtures")
    )
    let sourcesDir = fixturesDir.appendingPathComponent("sources")
    let configPath = fixturesDir.appendingPathComponent("provided-codegen.json")

    // Use ~/Library/Caches — writes in /var/folders are invisible to the parent
    // process on macOS 15 due to per-process filesystem namespace virtualisation.
    let caches = try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
    let outputDir = caches.appendingPathComponent("emit-wirelet-provided-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outputDir) }

    let executable = productsURL().appendingPathComponent("emit-wirelet-provided")
    try runCLI(executable: executable, config: configPath, source: sourcesDir, output: outputDir)

    // The emitter places <Service>.kt at interfacePackage (dots→slashes).
    let expectedPath = outputDir.appendingPathComponent(
        "io/github/jiyimeta/sample/provided/generated/TodoStore.kt"
    )
    #expect(FileManager.default.fileExists(atPath: expectedPath.path))

    if let content = try? String(contentsOf: expectedPath, encoding: .utf8) {
        #expect(content.contains("class TodoStoreNativeAdapter"))
    }
}

@Test func cliIsIdempotent() throws {
    let fixturesDir = try #require(
        Bundle.module.resourceURL?.appendingPathComponent("Fixtures")
    )
    let sourcesDir = fixturesDir.appendingPathComponent("sources")
    let configPath = fixturesDir.appendingPathComponent("provided-codegen.json")

    let caches = try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
    let outputDir = caches.appendingPathComponent("emit-wirelet-provided-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outputDir) }

    let executable = productsURL().appendingPathComponent("emit-wirelet-provided")
    try runCLI(executable: executable, config: configPath, source: sourcesDir, output: outputDir)

    let expectedPath = outputDir.appendingPathComponent(
        "io/github/jiyimeta/sample/provided/generated/TodoStore.kt"
    )

    // Idempotency: second run preserves mtime.
    let firstMtime = try mtime(of: expectedPath)
    try runCLI(executable: executable, config: configPath, source: sourcesDir, output: outputDir)
    let secondMtime = try mtime(of: expectedPath)
    #expect(firstMtime == secondMtime)
}

private func productsURL() -> URL {
    let testBundle = Bundle.module.bundleURL
    return testBundle.deletingLastPathComponent()
}

private func runCLI(
    executable: URL,
    config: URL,
    source: URL,
    output: URL,
    includePackages: [String] = []
) throws {
    let process = Process()
    process.executableURL = executable
    var args = [
        "--config", config.path,
        "--source", source.path,
        "--output", output.path,
    ]
    for pkg in includePackages {
        args.append("--include-package")
        args.append(pkg)
    }
    process.arguments = args
    let stderr = Pipe()
    process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 {
        let data = stderr.fileHandleForReading.readDataToEndOfFile()
        let msg = String(data: data, encoding: .utf8) ?? ""
        Issue.record("CLI failed: \(msg)")
    }
}

private func mtime(of url: URL) throws -> Date {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    return attrs[.modificationDate] as? Date ?? .distantPast
}
