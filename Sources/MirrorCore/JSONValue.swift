import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
    public subscript(key: String) -> JSONValue {
        if case .object(let object) = self { return object[key] ?? .null }
        return .null
    }
    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }
    public var array: [JSONValue] {
        if case .array(let value) = self { return value }
        return []
    }
    public var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }
    public var formatted: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self), let result = String(data: data, encoding: .utf8)
        else { return "[Unavailable structured content]" }
        return result
    }
}

public enum ReadOnlyRPC {
    public static let methods: Set<String> = [
        "initialize", "thread/list", "thread/read", "thread/turns/list",
    ]
}
