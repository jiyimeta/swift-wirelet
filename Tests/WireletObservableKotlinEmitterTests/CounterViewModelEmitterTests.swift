import Foundation
import Testing
import WireletKotlinEmitter
@testable import WireletObservableKotlinEmitter
import WireletObservableSchema

@Test func emitsCounterViewModel() throws {
    let vm = ObservableViewModel(
        name: "CounterVM",
        properties: [
            ObservableProperty(
                name: "count",
                swiftTypeText: "Int32",
                kind: .primitive,
                isMutable: true,
            ),
        ],
        methods: [],
    )
    let config = ObservableCodegenConfig(
        viewModelPackage: "com.example.app.viewmodels",
        modelPackage: "com.example.app.model",
        codecPackage: "com.example.app.codecs",
        libraryName: "CounterJNI",
        nameTransform: .stripSuffix("VM"),
    )

    let files = ObservableKotlinEmitter(config: config)
        .emit(schema: ObservableSchema(viewModels: [vm]))

    #expect(files.count == 1)
    let actual = try #require(files.first)
    #expect(
        actual.relativePath ==
            "com/example/app/viewmodels/CounterViewModel.kt",
    )

    let url = try #require(Bundle.module.url(
        forResource: "CounterViewModel.expected",
        withExtension: "kt",
        subdirectory: "Fixtures",
    ))
    let expected = try String(contentsOf: url, encoding: .utf8)
    if actual.content != expected {
        // Dump the actual output to /tmp so the human (or you) can compare.
        try? actual.content.write(
            toFile: "/tmp/CounterViewModel.actual.kt",
            atomically: true,
            encoding: .utf8,
        )
        Issue.record("""
        Golden mismatch. Actual written to /tmp/CounterViewModel.actual.kt.
        Diff:
        \(diff(expected: expected, actual: actual.content))
        """)
    }
}

private func diff(expected: String, actual: String) -> String {
    let e = expected.split(separator: "\n", omittingEmptySubsequences: false)
    let a = actual.split(separator: "\n", omittingEmptySubsequences: false)
    var out: [String] = []
    let n = max(e.count, a.count)
    for i in 0 ..< n {
        let l = i < e.count ? String(e[i]) : "<EOF>"
        let r = i < a.count ? String(a[i]) : "<EOF>"
        if l != r {
            out.append("L\(i + 1):")
            out.append("- \(l)")
            out.append("+ \(r)")
        }
    }
    return out.joined(separator: "\n")
}
