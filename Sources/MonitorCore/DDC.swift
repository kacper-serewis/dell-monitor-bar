import Foundation

public enum DDCError: Error, LocalizedError, Equatable {
    case invalidReply, unsupported, notReady, capabilityLimit, unadvertised, invalidValue, verificationFailed
    public var errorDescription: String? {
        switch self {
        case .invalidReply: return "The monitor returned an invalid reply. Try Refresh."
        case .unsupported: return "The monitor does not support this control."
        case .notReady: return "The monitor is not responding. Enable DDC/CI in its on-screen menu."
        case .capabilityLimit: return "The monitor's capability data is incomplete."
        case .unadvertised: return "This monitor does not advertise that setting."
        case .invalidValue: return "The requested value is outside the monitor's range."
        case .verificationFailed: return "The monitor did not apply the setting. Check its picture mode or HDR settings."
        }
    }
}

public struct VCPValue: Equatable {
    public let current: UInt16
    public let maximum: UInt16
}

public enum DDCPacket {
    private static func frame(_ payload: [UInt8]) -> [UInt8] {
        let data = [UInt8(0x80 | payload.count)] + payload
        return data + [data.reduce(0x6E ^ 0x51, ^)]
    }
    public static func get(_ code: UInt8) -> [UInt8] { frame([0x01, code]) }
    public static func set(_ code: UInt8, _ value: UInt16) -> [UInt8] {
        frame([0x03, code, UInt8(value >> 8), UInt8(value & 0xFF)])
    }
    public static func capabilities(_ offset: UInt16) -> [UInt8] {
        frame([0xF3, UInt8(offset >> 8), UInt8(offset & 0xFF)])
    }
    private static func envelope(_ bytes: [UInt8]) throws -> Int {
        guard bytes.count >= 3, bytes[0] == 0x6E, bytes[1] & 0x80 != 0 else { throw DDCError.invalidReply }
        let size = Int(bytes[1] & 0x7F)
        guard bytes.count >= size + 3,
              bytes.prefix(size + 3).reduce(UInt8(0x50), ^) == 0 else { throw DDCError.invalidReply }
        guard size > 0 else { throw DDCError.notReady }
        return size
    }
    public static func value(_ bytes: [UInt8], code: UInt8) throws -> VCPValue {
        guard try envelope(bytes) == 8, bytes[2] == 0x02, bytes[4] == code else { throw DDCError.invalidReply }
        guard bytes[3] == 0 else { throw DDCError.unsupported }
        return VCPValue(current: UInt16(bytes[8]) << 8 | UInt16(bytes[9]),
                        maximum: UInt16(bytes[6]) << 8 | UInt16(bytes[7]))
    }
    public static func fragment(_ bytes: [UInt8], offset: UInt16) throws -> [UInt8] {
        let size = try envelope(bytes)
        guard size >= 3, bytes[2] == 0xE3,
              UInt16(bytes[3]) << 8 | UInt16(bytes[4]) == offset else { throw DDCError.invalidReply }
        return Array(bytes[5..<(size + 2)])
    }
}

public protocol DDCTransport {
    /// A write with replyLength == 0 MUST be sent exactly once, including on error.
    func exchange(_ frame: [UInt8], replyLength: Int) throws -> [UInt8]
}

public final class DDCSession {
    private let transport: DDCTransport
    public init(transport: DDCTransport) { self.transport = transport }

    private func request<T>(_ frame: [UInt8], length: Int, decode: ([UInt8]) throws -> T) throws -> T {
        var last: Error = DDCError.notReady
        for _ in 0..<3 {
            do { return try decode(transport.exchange(frame, replyLength: length)) }
            catch DDCError.unsupported { throw DDCError.unsupported }
            catch { last = error }
        }
        throw last
    }
    public func read(_ code: UInt8) throws -> VCPValue {
        try request(DDCPacket.get(code), length: 12) { try DDCPacket.value($0, code: code) }
    }
    public func capabilities() throws -> Capabilities {
        var result: [UInt8] = []
        for _ in 0..<256 {
            let offset = UInt16(result.count)
            let part = try request(DDCPacket.capabilities(offset), length: 40) {
                try DDCPacket.fragment($0, offset: offset)
            }
            if part.isEmpty || part.contains(0) {
                result += part.prefix(while: { $0 != 0 })
                guard let string = String(bytes: result, encoding: .ascii) else { throw DDCError.invalidReply }
                return try Capabilities(raw: string)
            }
            result += part
            guard result.count < 4096 else { throw DDCError.capabilityLimit }
        }
        throw DDCError.capabilityLimit
    }
    public func setLevel(_ code: UInt8, value: UInt16, capabilities: Capabilities) throws -> VCPValue {
        guard code == 0x10 || code == 0x12, capabilities.supports(code) else { throw DDCError.unadvertised }
        let before = try read(code)
        guard before.maximum > 0, value <= before.maximum else { throw DDCError.invalidValue }
        try writeSetting(code, value)
        let after = try read(code)
        guard after.current == value else { throw DDCError.verificationFailed }
        return after
    }
    public func setInput(_ input: UInt16, capabilities: Capabilities) throws {
        guard input <= 0xFF, capabilities.inputs.contains(UInt8(input)) else { throw DDCError.unadvertised }
        try writeSetting(0x60, input)
    }
    private func writeSetting(_ code: UInt8, _ value: UInt16) throws {
        // Dell panels can ignore a single SET. Two identical writes are safe for
        // absolute levels/input selection. This policy MUST NOT apply to actions.
        let frame = DDCPacket.set(code, value)
        _ = try transport.exchange(frame, replyLength: 0)
        _ = try transport.exchange(frame, replyLength: 0)
    }
    public func switchUSB(capabilities: Capabilities) throws {
        guard capabilities.supports(0xE7) else { throw DDCError.unadvertised }
        // This is an action, not a state. Never retry it, verify it by reading E7,
        // or change USB association fields with unverified model-specific packing.
        _ = try transport.exchange(DDCPacket.set(0xE7, 0xFF00), replyLength: 0)
    }
}
