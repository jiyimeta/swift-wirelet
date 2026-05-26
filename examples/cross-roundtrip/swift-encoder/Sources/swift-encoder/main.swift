import Foundation
import SharedSchema

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift-encoder <output-path>\n".utf8))
    exit(2)
}

let outPath = CommandLine.arguments[1]
let message = Message(id: 42, text: "hello", tags: ["a", "b"])
let data = message.encodeToData()
try data.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(data.count) bytes to \(outPath)")
