// Resolves the directory containing the cross-language conformance
// fixtures. Independent of cwd — uses #filePath relative to this file.

import Foundation

enum FixtureLocator {
    /// `kotlin/conformance-tests/fixtures/` at the wirelet package root.
    static let fixturesURL: URL = {
        // This file is at Tests/ConformanceTests/FixtureURL.swift.
        // Walk up two components → package root.
        let thisFile = URL(fileURLWithPath: #filePath)
        let packageRoot = thisFile
            .deletingLastPathComponent()  // ConformanceTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // wirelet/
        return packageRoot
            .appendingPathComponent("kotlin", isDirectory: true)
            .appendingPathComponent("conformance-tests", isDirectory: true)
            .appendingPathComponent("fixtures", isDirectory: true)
    }()
}
