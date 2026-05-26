import Wirelet

@WireFormat
public struct Message {
    public var id: Int32
    public var text: String
    public var tags: [String]

    public init(id: Int32, text: String, tags: [String]) {
        self.id = id
        self.text = text
        self.tags = tags
    }
}
