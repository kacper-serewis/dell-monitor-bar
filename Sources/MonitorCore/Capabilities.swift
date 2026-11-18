import Foundation

public struct Capabilities: Equatable {
    public let raw: String
    public let codes: [UInt8: [UInt16]]
    public var inputs: [UInt8] { (codes[0x60] ?? []).compactMap(UInt8.init(exactly:)) }
    public func supports(_ code: UInt8) -> Bool { codes[code] != nil }

    public init(raw: String) throws {
        self.raw = raw
        // Require a complete, balanced capability string before enabling writes.
        var depth = 0
        for char in raw {
            if char == "(" { depth += 1 }
            if char == ")" { depth -= 1 }
            guard depth >= 0 else { throw DDCError.invalidReply }
        }
        guard depth == 0,
              let range = raw.range(of: "vcp(", options: .caseInsensitive) else { throw DDCError.invalidReply }
        let chars = Array(raw[range.upperBound...])
        var i = 0
        var parsed: [UInt8: [UInt16]] = [:]
        func whitespace() { while i < chars.count && chars[i].isWhitespace { i += 1 } }
        func hex() throws -> UInt16 {
            let start = i
            while i < chars.count && chars[i].isHexDigit { i += 1 }
            guard i > start, i - start <= 4, let value = UInt16(String(chars[start..<i]), radix: 16) else {
                throw DDCError.invalidReply
            }
            return value
        }
        var closed = false
        while i < chars.count {
            whitespace()
            guard i < chars.count else { break }
            if chars[i] == ")" { closed = true; break }
            let rawCode = try hex()
            guard let code = UInt8(exactly: rawCode) else { throw DDCError.invalidReply }
            whitespace()
            var values: [UInt16] = []
            if i < chars.count && chars[i] == "(" {
                i += 1
                whitespace()
                while i < chars.count && chars[i] != ")" {
                    values.append(try hex())
                    whitespace()
                }
                guard i < chars.count else { throw DDCError.invalidReply }
                i += 1
            }
            parsed[code] = values
        }
        guard closed, !parsed.isEmpty else { throw DDCError.invalidReply }
        codes = parsed
    }

    public static func inputName(_ code: UInt8) -> String {
        switch code {
        case 0x0F: return "DisplayPort"
        case 0x10: return "DisplayPort 2"
        case 0x11: return "HDMI"
        case 0x12: return "HDMI 2"
        case 0x13: return "DisplayPort 2"
        case 0x19: return "Thunderbolt"
        case 0x1B: return "USB-C"
        default: return String(format: "Input 0x%02X", code)
        }
    }
}
