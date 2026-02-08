import XCTest
@testable import Tabbed

final class TabTooltipTests: XCTestCase {
    func testShortTitleNotTruncated() {
        XCTAssertFalse(TabBarView.isTitleTruncated(title: "Mail", tabWidth: 200))
    }

    func testLongTitleTruncatedAtNarrowWidth() {
        let longTitle = "Untitled Document - Google Chrome - Default Profile"
        XCTAssertTrue(TabBarView.isTitleTruncated(title: longTitle, tabWidth: 80))
    }

    func testLongTitleNotTruncatedAtWideWidth() {
        let longTitle = "Untitled Document - Google Chrome"
        XCTAssertFalse(TabBarView.isTitleTruncated(title: longTitle, tabWidth: 500))
    }

    func testEmptyTitleNotTruncated() {
        XCTAssertFalse(TabBarView.isTitleTruncated(title: "", tabWidth: 50))
    }

    func testZeroWidthAlwaysTruncated() {
        XCTAssertTrue(TabBarView.isTitleTruncated(title: "X", tabWidth: 0))
    }
}
