// Copied from Afterglow (Shared/JSONValue.swift).
import Foundation

/// A Tuya data-point value. The cloud sends bools, ints, enum strings and the odd raw/JSON blob.
enum JSONValue: Codable, Hashable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .null: try c.encodeNil()
        }
    }

    /// Converts a JSONSerialization value, keeping NSNumber booleans apart from 0/1.
    static func from(_ any: Any?) -> JSONValue {
        guard let any else { return .null }
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            let type = String(cString: n.objCType)
            if type == "d" || type == "f" {
                let d = n.doubleValue
                return d == d.rounded() && abs(d) < 1e15 ? .int(Int(d)) : .double(d)
            }
            return .int(n.intValue)
        }
        if let s = any as? String { return .string(s) }
        if any is NSNull { return .null }
        if JSONSerialization.isValidJSONObject(any),
           let data = try? JSONSerialization.data(withJSONObject: any),
           let s = String(data: data, encoding: .utf8) {
            return .string(s)
        }
        return .null
    }

    var any: Any {
        switch self {
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        case .null: return NSNull()
        }
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .int(let i): return i != 0
        case .string(let s): return s == "true" ? true : (s == "false" ? false : nil)
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .int(let i): return Double(i)
        case .double(let d): return d
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        case .null: return nil
        }
    }

    var display: String { stringValue ?? "–" }
}
