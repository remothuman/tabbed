import XCTest
@testable import Tabbed

final class ScreenCompensationTests: XCTestCase {

    // MARK: - clampResult

    func testClampResult_windowAtTopOfScreen_squeezesDown() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let windowFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)

        let result = ScreenCompensation.clampResult(frame: windowFrame, visibleFrame: visibleFrame)

        XCTAssertEqual(result.frame.origin.y, 25 + 28)
        XCTAssertEqual(result.frame.size.height, 875 - 28)
        XCTAssertEqual(result.squeezeDelta, 28)
    }

    func testClampResult_windowBelowTabBarZone_noSqueeze() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let windowFrame = CGRect(x: 100, y: 200, width: 800, height: 600)

        let result = ScreenCompensation.clampResult(frame: windowFrame, visibleFrame: visibleFrame)

        XCTAssertEqual(result.frame, windowFrame)
        XCTAssertEqual(result.squeezeDelta, 0)
    }

    func testClampResult_windowPartiallyInTabBarZone_squeezesByPartialAmount() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let windowFrame = CGRect(x: 100, y: 35, width: 800, height: 600)

        let result = ScreenCompensation.clampResult(frame: windowFrame, visibleFrame: visibleFrame)

        XCTAssertEqual(result.squeezeDelta, 18)
        XCTAssertEqual(result.frame.origin.y, 53)
        XCTAssertEqual(result.frame.size.height, 582)
    }

    func testClampResult_heightNeverBelowTabBarHeight() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let windowFrame = CGRect(x: 100, y: 25, width: 400, height: 30)

        let result = ScreenCompensation.clampResult(frame: windowFrame, visibleFrame: visibleFrame)

        XCTAssertEqual(result.frame.size.height, 28)
    }

    // MARK: - isMaximized

    func testIsMaximized_exactMatch_returnsTrue() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let groupFrame = CGRect(x: 0, y: 53, width: 1440, height: 847)
        let squeezeDelta: CGFloat = 28

        XCTAssertTrue(ScreenCompensation.isMaximized(
            groupFrame: groupFrame, squeezeDelta: squeezeDelta, visibleFrame: visibleFrame
        ))
    }

    func testIsMaximized_withinTolerance_returnsTrue() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let groupFrame = CGRect(x: 5, y: 58, width: 1435, height: 842)
        let squeezeDelta: CGFloat = 28

        XCTAssertTrue(ScreenCompensation.isMaximized(
            groupFrame: groupFrame, squeezeDelta: squeezeDelta, visibleFrame: visibleFrame
        ))
    }

    func testIsMaximized_tooFarOff_returnsFalse() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let groupFrame = CGRect(x: 100, y: 200, width: 800, height: 600)
        let squeezeDelta: CGFloat = 0

        XCTAssertFalse(ScreenCompensation.isMaximized(
            groupFrame: groupFrame, squeezeDelta: squeezeDelta, visibleFrame: visibleFrame
        ))
    }

    func testIsMaximized_noSqueeze_fullScreen() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let groupFrame = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let squeezeDelta: CGFloat = 0

        XCTAssertTrue(ScreenCompensation.isMaximized(
            groupFrame: groupFrame, squeezeDelta: squeezeDelta, visibleFrame: visibleFrame
        ))
    }

    // MARK: - expandFrame

    func testExpandFrame_withDelta_expandsUpward() {
        let frame = CGRect(x: 0, y: 53, width: 1440, height: 847)
        let expanded = ScreenCompensation.expandFrame(frame, undoingSqueezeDelta: 28)

        XCTAssertEqual(expanded.origin.y, 25)
        XCTAssertEqual(expanded.size.height, 875)
        XCTAssertEqual(expanded.origin.x, 0)
        XCTAssertEqual(expanded.size.width, 1440)
    }

    func testExpandFrame_zeroDelta_noChange() {
        let frame = CGRect(x: 100, y: 200, width: 800, height: 600)
        let expanded = ScreenCompensation.expandFrame(frame, undoingSqueezeDelta: 0)

        XCTAssertEqual(expanded, frame)
    }
}
