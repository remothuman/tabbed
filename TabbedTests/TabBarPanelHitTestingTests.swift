import XCTest
@testable import Tabbed

final class TabBarPanelHitTestingTests: XCTestCase {
    func testGroupNameDragRegionIncludesLeadingAndTrailingEdges() {
        XCTAssertTrue(
            TabBarPanel.isGroupNameDragRegion(
                pointX: 20,
                leadingPad: 4,
                handleWidth: 16,
                groupNameWidth: 80
            )
        )
        XCTAssertTrue(
            TabBarPanel.isGroupNameDragRegion(
                pointX: 100,
                leadingPad: 4,
                handleWidth: 16,
                groupNameWidth: 80
            )
        )
    }

    func testGroupNameDragRegionRejectsPointsOutsideBounds() {
        XCTAssertFalse(
            TabBarPanel.isGroupNameDragRegion(
                pointX: 19.99,
                leadingPad: 4,
                handleWidth: 16,
                groupNameWidth: 80
            )
        )
        XCTAssertFalse(
            TabBarPanel.isGroupNameDragRegion(
                pointX: 100.01,
                leadingPad: 4,
                handleWidth: 16,
                groupNameWidth: 80
            )
        )
    }

    func testGroupNameDragRegionAccountsForHiddenHandleLayout() {
        XCTAssertTrue(
            TabBarPanel.isGroupNameDragRegion(
                pointX: 2,
                leadingPad: 2,
                handleWidth: 0,
                groupNameWidth: 40
            )
        )
        XCTAssertFalse(
            TabBarPanel.isGroupNameDragRegion(
                pointX: 1.99,
                leadingPad: 2,
                handleWidth: 0,
                groupNameWidth: 40
            )
        )
    }

    func testGroupNameDragRegionIsDisabledWhenWidthIsNonPositive() {
        XCTAssertFalse(
            TabBarPanel.isGroupNameDragRegion(
                pointX: 20,
                leadingPad: 4,
                handleWidth: 16,
                groupNameWidth: 0
            )
        )
        XCTAssertFalse(
            TabBarPanel.isGroupNameDragRegion(
                pointX: 20,
                leadingPad: 4,
                handleWidth: 16,
                groupNameWidth: -1
            )
        )
    }
}
