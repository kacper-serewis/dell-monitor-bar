import XCTest
@testable import MonitorCore

final class LevelAdjustmentsTests: XCTestCase {
    let brightness = LevelControlID(monitorID: "first", code: 0x10)
    let contrast = LevelControlID(monitorID: "first", code: 0x12)
    let other = LevelControlID(monitorID: "second", code: 0x10)

    func testDragIsImmediateEvenWhileConfirmedValueIsOld() throws {
        var levels = LevelAdjustments()
        levels.setEditing(brightness, true)
        levels.update(brightness, value: 42.4, maximum: 100)
        XCTAssertEqual(levels.value(for: brightness, confirmed: 100), 42.4)
        XCTAssertNil(levels.next(), "Dragging should not flood the monitor with writes")
        levels.setEditing(brightness, false)
        let write = try XCTUnwrap(levels.next())
        XCTAssertEqual(write.value, 42)
        XCTAssertEqual(levels.value(for: brightness, confirmed: 100), 42.4)
        levels.complete(write)
        XCTAssertEqual(levels.value(for: brightness, confirmed: 42), 42)
    }

    func testLateReplyCannotOverwriteNewerDragOrQueuedTarget() throws {
        var levels = LevelAdjustments()
        levels.update(brightness, value: 70, maximum: 100)
        levels.setEditing(brightness, false)
        let first = try XCTUnwrap(levels.next())
        levels.setEditing(brightness, true)
        levels.update(brightness, value: 30, maximum: 100)
        levels.complete(first)
        XCTAssertEqual(levels.value(for: brightness, confirmed: 70), 30)
        levels.setEditing(brightness, false)
        let second = try XCTUnwrap(levels.next())
        XCTAssertEqual(second.value, 30)
        levels.complete(first) // A stale completion still cannot clear the new request.
        XCTAssertEqual(levels.value(for: brightness, confirmed: 70), 30)
        levels.complete(second)
        XCTAssertEqual(levels.value(for: brightness, confirmed: 30), 30)
    }

    func testBusyAdjustmentsCoalesceToLatestValueIncludingReturnToOriginal() throws {
        var levels = LevelAdjustments()
        levels.update(brightness, value: 70, maximum: 100)
        levels.setEditing(brightness, false)
        let first = try XCTUnwrap(levels.next())
        for value in [60.0, 40.0, 100.0] {
            levels.update(brightness, value: value, maximum: 100)
            levels.setEditing(brightness, false)
        }
        levels.complete(first)
        XCTAssertEqual(levels.value(for: brightness, confirmed: 70), 100)
        XCTAssertEqual(try XCTUnwrap(levels.next()).value, 100)
        XCTAssertNil(levels.next(), "Intermediate targets should be replaced, not replayed")
    }

    func testFailureRollsBackOnlyItsOwnDraft() throws {
        var levels = LevelAdjustments()
        levels.update(brightness, value: 40, maximum: 100)
        levels.setEditing(brightness, false)
        let write = try XCTUnwrap(levels.next())
        levels.complete(write) // Failed write; confirmed device state is still 75.
        XCTAssertEqual(levels.value(for: brightness, confirmed: 75), 75)
        XCTAssertEqual(levels.value(for: contrast, confirmed: 60), 60)
    }

    func testInProgressGestureIsNotResetByCompletionAndDoesNotBlockOtherSlider() throws {
        var levels = LevelAdjustments()
        levels.update(brightness, value: 50, maximum: 100)
        levels.setEditing(brightness, false)
        let first = try XCTUnwrap(levels.next())
        levels.setEditing(brightness, true)
        levels.complete(first)
        XCTAssertEqual(levels.value(for: brightness, confirmed: 100), 50)
        levels.update(other, value: 20, maximum: 100)
        levels.setEditing(other, false)
        XCTAssertEqual(try XCTUnwrap(levels.next()).control, other)
        levels.setEditing(brightness, false)
        XCTAssertEqual(try XCTUnwrap(levels.next()).value, 50)
    }

    func testDisconnectRemovesDraftAndQueuedWrite() {
        var levels = LevelAdjustments()
        levels.update(brightness, value: 40, maximum: 100)
        levels.setEditing(brightness, false)
        levels.retainMonitors(["second"])
        XCTAssertNil(levels.next())
        XCTAssertEqual(levels.value(for: brightness, confirmed: 80), 80)
    }
}
