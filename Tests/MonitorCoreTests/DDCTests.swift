import XCTest
@testable import MonitorCore

final class DDCTests: XCTestCase {
    private func reply(_ payload: [UInt8]) -> [UInt8] {
        let body: [UInt8] = [0x6E, 0x80 | UInt8(payload.count)] + payload
        return body + [body.reduce(0x50, ^)]
    }
    private func value(_ code: UInt8, _ current: UInt16, max: UInt16 = 100) -> [UInt8] {
        reply([0x02, 0, code, 0, UInt8(max >> 8), UInt8(max & 255), UInt8(current >> 8), UInt8(current & 255)])
    }

    func testKnownWireFrames() {
        XCTAssertEqual(DDCPacket.get(0x10), [0x82, 0x01, 0x10, 0xAC])
        XCTAssertEqual(DDCPacket.set(0x10, 50), [0x84, 0x03, 0x10, 0, 0x32, 0x9A])
        XCTAssertEqual(DDCPacket.set(0xE7, 0xFF00), [0x84, 0x03, 0xE7, 0xFF, 0, 0xA0])
    }

    func testReplyValidationAndSixteenBitValues() throws {
        let valid = value(0x60, 0x1B1B, max: 0x1234)
        let decoded = try DDCPacket.value(valid + [0xAA, 0xBB], code: 0x60)
        XCTAssertEqual(decoded.current, 0x1B1B)
        XCTAssertEqual(decoded.maximum, 0x1234)
        for index in valid.indices {
            var broken = valid
            broken[index] ^= 1
            XCTAssertThrowsError(try DDCPacket.value(broken, code: 0x60))
        }
        for count in 0..<valid.count {
            XCTAssertThrowsError(try DDCPacket.value(Array(valid.prefix(count)), code: 0x60))
        }
        XCTAssertThrowsError(try DDCPacket.value(valid, code: 0x10))
        XCTAssertThrowsError(try DDCPacket.value([0x6E, 0x80, 0xBE], code: 0x10)) {
            XCTAssertEqual($0 as? DDCError, .notReady)
        }
        XCTAssertThrowsError(try DDCPacket.value(reply([2, 1, 0x10, 0, 0, 100, 0, 50]), code: 0x10)) {
            XCTAssertEqual($0 as? DDCError, .unsupported)
        }
    }

    func testCapabilitiesAreModelSpecific() throws {
        let p = try Capabilities(raw: "(prot(monitor)model(P2725QE)vcp(10 12 60(1B 0F 11) E2(00 02 04) EA(F800 F801)))")
        let u = try Capabilities(raw: "(prot(monitor)model(U2723QE)vcp(10 12 60(1B 0F 11) E7(02 03) E9(00 01 02 21 22 24)))")
        XCTAssertEqual(p.inputs, [27, 15, 17])
        XCTAssertFalse(p.supports(0xE7))
        XCTAssertEqual(p.codes[0xEA], [0xF800, 0xF801], "P2725QE advertises 16-bit vendor values")
        XCTAssertTrue(u.supports(0xE7))
        XCTAssertFalse(u.supports(0xEE))
        for malformed in ["", "vcp(", "(vcp(10 60(1B)))extra)", "(vcp(10 ZZ))", "(vcp(100))", "(vcp())"] {
            XCTAssertThrowsError(try Capabilities(raw: malformed), malformed)
        }
    }

    func testCapabilityPagingRejectsWrongOffsetsAndTruncation() throws {
        let first = "(vcp(10 60(1B "
        let second = "0F 11)))"
        let transport = FakeTransport([
            .success(reply([0xE3, 0, 0] + Array(first.utf8))),
            .success(reply([0xE3, 0, UInt8(first.utf8.count)] + Array(second.utf8))),
            .success(reply([0xE3, 0, UInt8(first.utf8.count + second.utf8.count)]))
        ])
        let caps = try DDCSession(transport: transport).capabilities()
        XCTAssertEqual(caps.inputs, [27, 15, 17])
        XCTAssertEqual(transport.frames[1].0, DDCPacket.capabilities(UInt16(first.utf8.count)))
        XCTAssertThrowsError(try DDCPacket.fragment(reply([0xE3, 0, 1, 65]), offset: 0))
        let truncated = FakeTransport([.success(reply([0xE3, 0, 0] + Array("(vcp(10".utf8))),
                                       .success(reply([0xE3, 0, 7]))])
        XCTAssertThrowsError(try DDCSession(transport: truncated).capabilities())
    }

    func testKVMIsSentExactlyOnceAndNeverReadBack() throws {
        let caps = try Capabilities(raw: "(vcp(E7(02 03)))")
        let transport = FakeTransport([.success([])])
        try DDCSession(transport: transport).switchUSB(capabilities: caps)
        XCTAssertEqual(transport.frames.count, 1)
        XCTAssertEqual(transport.frames[0].0, DDCPacket.set(0xE7, 0xFF00))
        XCTAssertEqual(transport.frames[0].1, 0)

        let failure = FakeTransport([.failure(DDCError.notReady)])
        XCTAssertThrowsError(try DDCSession(transport: failure).switchUSB(capabilities: caps))
        XCTAssertEqual(failure.frames.count, 1, "A failed action could already have taken effect")
    }

    func testUnsupportedWritesNeverReachTransport() throws {
        let p = try Capabilities(raw: "(vcp(10 12 60(1B 0F 11)))")
        let transport = FakeTransport([])
        let session = DDCSession(transport: transport)
        XCTAssertThrowsError(try session.switchUSB(capabilities: p))
        XCTAssertThrowsError(try session.setInput(0x12, capabilities: p))
        XCTAssertThrowsError(try session.setInput(0x11B, capabilities: p))
        XCTAssertThrowsError(try session.setLevel(0xD6, value: 5, capabilities: p))
        XCTAssertTrue(transport.frames.isEmpty)
    }

    func testAbsoluteInputIsRepeatedWithoutReadback() throws {
        let caps = try Capabilities(raw: "(vcp(60(1B 0F 11)))")
        let transport = FakeTransport([.success([]), .success([])])
        try DDCSession(transport: transport).setInput(0x11, capabilities: caps)
        XCTAssertEqual(transport.frames.count, 2)
        XCTAssertEqual(transport.frames[0].0, DDCPacket.set(0x60, 0x11))
        XCTAssertEqual(transport.frames[1].0, transport.frames[0].0)
    }

    func testLevelsReadBackAndRespectReportedMaximum() throws {
        let caps = try Capabilities(raw: "(vcp(10 12))")
        let transport = FakeTransport([.success(value(0x10, 100)), .success([]), .success([]), .success(value(0x10, 50))])
        XCTAssertEqual(try DDCSession(transport: transport).setLevel(0x10, value: 50, capabilities: caps).current, 50)
        let ignored = FakeTransport([.success(value(0x10, 100)), .success([]), .success([]), .success(value(0x10, 100))])
        XCTAssertThrowsError(try DDCSession(transport: ignored).setLevel(0x10, value: 50, capabilities: caps)) {
            XCTAssertEqual($0 as? DDCError, .verificationFailed)
        }
        let limited = FakeTransport([.success(value(0x10, 20, max: 50))])
        XCTAssertThrowsError(try DDCSession(transport: limited).setLevel(0x10, value: 60, capabilities: caps))
        XCTAssertEqual(limited.frames.count, 1)
    }

    func testReadsRetryNullButNotUnsupportedReplies() throws {
        let retry = FakeTransport([.success([0x6E, 0x80, 0xBE]), .success(value(0x10, 70))])
        XCTAssertEqual(try DDCSession(transport: retry).read(0x10).current, 70)
        XCTAssertEqual(retry.frames.count, 2)
        let unsupported = FakeTransport([.success(reply([2, 1, 0x10, 0, 0, 100, 0, 0]))])
        XCTAssertThrowsError(try DDCSession(transport: unsupported).read(0x10))
        XCTAssertEqual(unsupported.frames.count, 1)
    }
}

private final class FakeTransport: DDCTransport {
    var responses: [Result<[UInt8], Error>]
    var frames: [([UInt8], Int)] = []
    init(_ responses: [Result<[UInt8], Error>]) { self.responses = responses }
    func exchange(_ frame: [UInt8], replyLength: Int) throws -> [UInt8] {
        frames.append((frame, replyLength))
        guard !responses.isEmpty else { throw DDCError.invalidReply }
        return try responses.removeFirst().get()
    }
}
