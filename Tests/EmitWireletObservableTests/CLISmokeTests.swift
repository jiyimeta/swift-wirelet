import Foundation
import Testing

@Test func cliEmitsTodoListViewModel() throws {
    let fixturesDir = try #require(
        Bundle.module.resourceURL?.appendingPathComponent("Fixtures")
    )
    let sourcesDir = fixturesDir.appendingPathComponent("sources")
    let configPath = fixturesDir.appendingPathComponent("observable-codegen.json")

    // ~/Library/Caches — same rationale as in EmitWireletKotlinTests/CLISmokeTests.swift
    // (avoid /var/folders sandboxing that hides writes from the parent process).
    let caches = try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
    let outputDir = caches.appendingPathComponent("emit-wirelet-observable-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outputDir) }

    let executable = productsURL().appendingPathComponent("emit-wirelet-observable")
    try runCLI(executable: executable, config: configPath, source: sourcesDir, output: outputDir)

    let expectedPath = outputDir.appendingPathComponent(
        "io/github/jiyimeta/observablecounter/generated/TodoListViewModel.kt"
    )
    #expect(FileManager.default.fileExists(atPath: expectedPath.path))

    // Idempotency: second run preserves mtime.
    let firstMtime = try mtime(of: expectedPath)
    try runCLI(executable: executable, config: configPath, source: sourcesDir, output: outputDir)
    let secondMtime = try mtime(of: expectedPath)
    #expect(firstMtime == secondMtime)
}

@Test func cliIncludePackageFiltersOutput() throws {
    let fixturesDir = try #require(
        Bundle.module.resourceURL?.appendingPathComponent("Fixtures")
    )
    let sourcesDir = fixturesDir.appendingPathComponent("sources")
    let configPath = fixturesDir.appendingPathComponent("observable-codegen.json")

    let caches = try #require(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first)
    let outputDir = caches.appendingPathComponent("emit-wirelet-observable-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: outputDir) }

    let executable = productsURL().appendingPathComponent("emit-wirelet-observable")

    // Filtering by a non-matching package emits zero files.
    try runCLI(
        executable: executable, config: configPath, source: sourcesDir, output: outputDir,
        includePackages: ["io.example.other"]
    )
    let viewModelPath = outputDir.appendingPathComponent(
        "io/github/jiyimeta/observablecounter/generated/TodoListViewModel.kt"
    )
    #expect(!FileManager.default.fileExists(atPath: viewModelPath.path))

    // Matching package emits the expected file.
    try runCLI(
        executable: executable, config: configPath, source: sourcesDir, output: outputDir,
        includePackages: ["io.github.jiyimeta.observablecounter.generated"]
    )
    #expect(FileManager.default.fileExists(atPath: viewModelPath.path))
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
