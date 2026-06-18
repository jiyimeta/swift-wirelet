import Foundation
import Testing
import WireletObservableSwiftBridgesEmitter

// MARK: - Shared test support for SwiftBridgesEmitter golden-file tests

/// Writes `content` to a uniquely-named file inside a fresh temp directory and
/// returns its URL. Used by the emitter golden-file suites to stage in-memory
/// Swift source fixtures for `SwiftBridgesEmitter.emit(sources:)`.
func writeEmitterTmp(name: String, content: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("emitter-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url
}
