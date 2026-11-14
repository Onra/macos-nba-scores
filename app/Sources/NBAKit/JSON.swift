import Foundation

/// A lenient view on decoded JSON. ESPN's payloads are loose (a score is a string here, a number there),
/// so every lookup answers something: a missing key gives an empty value, never an error.
public struct JSON: @unchecked Sendable {
    public let raw: Any?

    public init(_ raw: Any?) {
        self.raw = raw is NSNull ? nil : raw
    }

    public init(data: Data) throws {
        self.init(try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
    }

    public subscript(key: String) -> JSON {
        JSON((raw as? [String: Any])?[key])
    }

    public subscript(index: Int) -> JSON {
        guard let array = raw as? [Any], array.indices.contains(index) else { return JSON(nil) }
        return JSON(array[index])
    }

    public var exists: Bool { raw != nil }
    public var array: [JSON] { (raw as? [Any])?.map { JSON($0) } ?? [] }

    public var string: String? {
        if let string = raw as? String { return string }
        if let number = raw as? NSNumber { return number.stringValue }
        return nil
    }

    /// The value as text, or "" when there is none.
    public var text: String { string ?? "" }

    public var int: Int? {
        if let string = raw as? String { return Int(string) }
        if let number = raw as? NSNumber { return number.intValue }
        return nil
    }

    public var double: Double? {
        if let string = raw as? String { return Double(string) }
        if let number = raw as? NSNumber { return number.doubleValue }
        return nil
    }

    public var bool: Bool? { raw as? Bool }
}
