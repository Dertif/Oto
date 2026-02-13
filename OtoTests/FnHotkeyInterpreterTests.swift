import XCTest
@testable import Oto

final class FnHotkeyInterpreterTests: XCTestCase {
    func testHoldModePressAndRelease() {
        let sut = FnHotkeyInterpreter()

        let start = sut.interpret(
            isFnPressed: true,
            mode: .hold,
            timestamp: 1.0,
            isProcessing: false
        )
        let stop = sut.interpret(
            isFnPressed: false,
            mode: .hold,
            timestamp: 1.2,
            isProcessing: false
        )

        XCTAssertEqual(start, .start)
        XCTAssertEqual(stop, .stop)
    }

    func testHoldModeIgnoresRepeatedFlagsNoise() {
        let sut = FnHotkeyInterpreter()

        let firstDown = sut.interpret(
            isFnPressed: true,
            mode: .hold,
            timestamp: 1.0,
            isProcessing: false
        )
        let repeatedDown = sut.interpret(
            isFnPressed: true,
            mode: .hold,
            timestamp: 1.05,
            isProcessing: false
        )
        let up = sut.interpret(
            isFnPressed: false,
            mode: .hold,
            timestamp: 1.2,
            isProcessing: false
        )
        let repeatedUp = sut.interpret(
            isFnPressed: false,
            mode: .hold,
            timestamp: 1.25,
            isProcessing: false
        )

        XCTAssertEqual(firstDown, .start)
        XCTAssertNil(repeatedDown)
        XCTAssertEqual(up, .stop)
        XCTAssertNil(repeatedUp)
    }

    func testDoubleTapTogglesWithinWindow() {
        let sut = FnHotkeyInterpreter(doubleTapWindow: 0.32)

        let firstDown = sut.interpret(
            isFnPressed: true,
            mode: .doubleTap,
            timestamp: 5.0,
            isProcessing: false
        )
        _ = sut.interpret(
            isFnPressed: false,
            mode: .doubleTap,
            timestamp: 5.05,
            isProcessing: false
        )
        let secondDown = sut.interpret(
            isFnPressed: true,
            mode: .doubleTap,
            timestamp: 5.30,
            isProcessing: false
        )

        XCTAssertNil(firstDown)
        XCTAssertEqual(secondDown, .toggle)
    }

    func testDoubleTapDoesNotToggleOutsideWindow() {
        let sut = FnHotkeyInterpreter(doubleTapWindow: 0.32)

        let firstDown = sut.interpret(
            isFnPressed: true,
            mode: .doubleTap,
            timestamp: 10.0,
            isProcessing: false
        )
        _ = sut.interpret(
            isFnPressed: false,
            mode: .doubleTap,
            timestamp: 10.1,
            isProcessing: false
        )
        let secondDown = sut.interpret(
            isFnPressed: true,
            mode: .doubleTap,
            timestamp: 10.5,
            isProcessing: false
        )

        XCTAssertNil(firstDown)
        XCTAssertNil(secondDown)
    }

    func testIgnoresActionsWhileProcessing() {
        let sut = FnHotkeyInterpreter()

        let result = sut.interpret(
            isFnPressed: true,
            mode: .hold,
            timestamp: 20.0,
            isProcessing: true
        )

        XCTAssertNil(result)
    }

    func testModeSwitchResetPreventsStaleDoubleTap() {
        let sut = FnHotkeyInterpreter(doubleTapWindow: 0.32)

        _ = sut.interpret(
            isFnPressed: true,
            mode: .doubleTap,
            timestamp: 30.0,
            isProcessing: false
        )
        _ = sut.interpret(
            isFnPressed: false,
            mode: .doubleTap,
            timestamp: 30.05,
            isProcessing: false
        )

        sut.reset(for: .hold)

        let holdDown = sut.interpret(
            isFnPressed: true,
            mode: .hold,
            timestamp: 30.1,
            isProcessing: false
        )
        let holdUp = sut.interpret(
            isFnPressed: false,
            mode: .hold,
            timestamp: 30.2,
            isProcessing: false
        )

        XCTAssertEqual(holdDown, .start)
        XCTAssertEqual(holdUp, .stop)
    }
}
