import XCTest
@testable import Tabbed

final class FocusPanelOrderingTests: XCTestCase {
    func testOrderPanelAboveFromFocusEventSkipsNonTargetDuringCommitSuppression() {
        let app = AppDelegate()
        let panel = TabBarPanel()
        var orderedWindowIDs: [CGWindowID] = []
        app.onFocusPanelOrdered = { orderedWindowIDs.append($0) }
        app.beginCommitEchoSuppression(targetWindowID: 42)

        app.orderPanelAboveFromFocusEvent(panel, windowID: 99)

        let settled = expectation(description: "wait for deferred ordering window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            settled.fulfill()
        }
        wait(for: [settled], timeout: 1.0)

        XCTAssertTrue(orderedWindowIDs.isEmpty)
    }

    func testOrderPanelAboveFromFocusEventKeepsTargetDuringCommitSuppression() {
        let app = AppDelegate()
        let panel = TabBarPanel()
        var orderedWindowIDs: [CGWindowID] = []
        app.onFocusPanelOrdered = { orderedWindowIDs.append($0) }
        app.beginCommitEchoSuppression(targetWindowID: 42)

        app.orderPanelAboveFromFocusEvent(panel, windowID: 42)

        let settled = expectation(description: "wait for deferred ordering window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            settled.fulfill()
        }
        wait(for: [settled], timeout: 1.0)

        XCTAssertEqual(orderedWindowIDs, [42, 42])
    }

    func testInvalidateDeferredFocusPanelOrderingCancelsPendingReplay() {
        let app = AppDelegate()
        let panel = TabBarPanel()
        var orderedWindowIDs: [CGWindowID] = []
        app.onFocusPanelOrdered = { orderedWindowIDs.append($0) }

        app.orderPanelAboveFromFocusEvent(panel, windowID: 77)
        app.invalidateDeferredFocusPanelOrdering()

        let settled = expectation(description: "wait for deferred ordering window")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            settled.fulfill()
        }
        wait(for: [settled], timeout: 1.0)

        XCTAssertEqual(orderedWindowIDs, [77])
    }

    func testPrepareCounterFocusTransitionStartsSuppressionWhenSwitchingWindow() {
        let app = AppDelegate()
        let initialGeneration = app.focusDrivenPanelOrderGeneration

        let shouldFocus = app.prepareCounterFocusTransition(targetWindowID: 101, focusedWindowID: nil)

        XCTAssertTrue(shouldFocus)
        XCTAssertEqual(app.pendingCommitEchoTargetWindowID, 101)
        XCTAssertTrue(app.isCommitEchoSuppressionActive)
        XCTAssertEqual(app.focusDrivenPanelOrderGeneration, initialGeneration &+ 1)
    }

    func testPrepareCounterFocusTransitionSkipsWhenAlreadyFocused() {
        let app = AppDelegate()
        let initialGeneration = app.focusDrivenPanelOrderGeneration

        let shouldFocus = app.prepareCounterFocusTransition(targetWindowID: 202, focusedWindowID: 202)

        XCTAssertFalse(shouldFocus)
        XCTAssertNil(app.pendingCommitEchoTargetWindowID)
        XCTAssertEqual(app.focusDrivenPanelOrderGeneration, initialGeneration)
    }
}
