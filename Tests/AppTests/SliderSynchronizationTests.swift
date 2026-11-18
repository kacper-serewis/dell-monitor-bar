import XCTest
@testable import DellMonitorBar
@testable import MonitorCore

final class SliderSynchronizationTests: XCTestCase {
    @MainActor func testDelayedHardwareCompletionKeepsNewestSliderValueAndDrainsQueue() async throws {
        let backend = DelayedBackend()
        let model = AppModel(automaticallyRefresh: false, backend: backend)
        model.monitors = await backend.scan(forceCapabilities: false)
        let monitor = try XCTUnwrap(model.monitors.first)

        model.updateLevel(monitor, code: 0x10, value: 70, maximum: 100)
        model.editLevel(monitor, code: 0x10, editing: false)
        try await eventually { await backend.writes == [70] }
        XCTAssertTrue(model.isBusy)

        for value in [60.0, 30.0] {
            model.updateLevel(monitor, code: 0x10, value: value, maximum: 100)
            model.editLevel(monitor, code: 0x10, editing: false)
        }
        XCTAssertEqual(displayed(model), 30, "The bound slider must update before hardware replies")
        await backend.finishWrite()
        try await eventually { await backend.writes == [70, 30] }
        XCTAssertEqual(model.monitors[0].brightness?.current, 70)
        XCTAssertEqual(displayed(model), 30, "An old readback must not move the knob or percentage")

        await backend.finishWrite()
        try await eventually { !model.isBusy }
        XCTAssertEqual(model.monitors[0].brightness?.current, 30)
        XCTAssertEqual(displayed(model), 30)
    }

    @MainActor func testFailedWriteResynchronizesWithConfirmedValue() async throws {
        let backend = DelayedBackend()
        let model = AppModel(automaticallyRefresh: false, backend: backend)
        model.monitors = await backend.scan(forceCapabilities: false)
        let monitor = try XCTUnwrap(model.monitors.first)
        model.updateLevel(monitor, code: 0x10, value: 40, maximum: 100)
        model.editLevel(monitor, code: 0x10, editing: false)
        try await eventually { await backend.writes == [40] }
        XCTAssertEqual(displayed(model), 40)
        await backend.finishWrite(failing: true)
        try await eventually { !model.isBusy }
        XCTAssertEqual(displayed(model), 100)
        XCTAssertTrue(model.messageIsError)
    }

    @MainActor private func displayed(_ model: AppModel) -> Double {
        let monitor = model.monitors[0]
        return model.displayedLevel(monitor, code: 0x10, reading: monitor.brightness!)
    }

    @MainActor private func eventually(_ condition: () async -> Bool) async throws {
        for _ in 0..<1000 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTFail("Timed out waiting for queued slider work")
        throw DDCError.notReady
    }
}

private actor DelayedBackend: MonitorServing {
    private(set) var writes: [UInt16] = []
    private var confirmed: UInt16 = 100
    private var pending: (UInt16, CheckedContinuation<VCPValue, Error>)?

    func scan(forceCapabilities: Bool) -> [MonitorState] {
        [MonitorState(id: "test", name: "Test monitor", brightness: VCPValue(current: confirmed, maximum: 100))]
    }
    func level(_ id: String, code: UInt8, value: UInt16) async throws -> VCPValue {
        writes.append(value)
        return try await withCheckedThrowingContinuation { pending = (value, $0) }
    }
    func finishWrite(failing: Bool = false) {
        guard let (value, continuation) = pending else { return }
        pending = nil
        if failing { continuation.resume(throwing: DDCError.verificationFailed) }
        else {
            confirmed = value
            continuation.resume(returning: VCPValue(current: value, maximum: 100))
        }
    }
    func input(_ id: String, value: UInt8) {}
    func switchUSB(_ id: String) {}
}
