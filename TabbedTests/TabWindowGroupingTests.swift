import XCTest
@testable import Tabbed

final class TabWindowGroupingTests: XCTestCase {
    private func makeWindow(id: CGWindowID, pinned: Bool = false) -> WindowInfo {
        let element = AXUIElementCreateSystemWide()
        return WindowInfo(
            id: id,
            element: element,
            ownerPID: 1,
            bundleID: "com.test",
            title: "W\(id)",
            appName: "Test",
            icon: nil,
            isPinned: pinned
        )
    }

    func testSegmentsWithoutSplitsReturnSingleManagedSegment() {
        let w1 = makeWindow(id: 1, pinned: true)
        let w2 = makeWindow(id: 2)
        let separator = WindowInfo.separator(withID: 9_999)
        let w3 = makeWindow(id: 3)
        let group = TabGroup(windows: [w1, separator, w2, w3], frame: .zero)

        let segments = TabWindowGrouping.segments(
            in: group,
            splitPinnedTabs: false,
            splitOnSeparators: false
        )

        XCTAssertEqual(segments, [[1, 2, 3]])
    }

    func testSegmentsSplitPinnedTabsSeparatesPinnedFromUnpinned() {
        let w1 = makeWindow(id: 1, pinned: true)
        let w2 = makeWindow(id: 2, pinned: true)
        let w3 = makeWindow(id: 3)
        let w4 = makeWindow(id: 4)
        let group = TabGroup(windows: [w1, w2, w3, w4], frame: .zero)

        let segments = TabWindowGrouping.segments(
            in: group,
            splitPinnedTabs: true,
            splitOnSeparators: false
        )

        XCTAssertEqual(segments, [[1, 2], [3, 4]])
    }

    func testSegmentsSplitOnSeparatorsUsesSeparatorBoundaries() {
        let w1 = makeWindow(id: 1)
        let separatorA = WindowInfo.separator(withID: 9_998)
        let w2 = makeWindow(id: 2)
        let w3 = makeWindow(id: 3)
        let separatorB = WindowInfo.separator(withID: 9_997)
        let w4 = makeWindow(id: 4)
        let group = TabGroup(windows: [w1, separatorA, w2, w3, separatorB, w4], frame: .zero)

        let segments = TabWindowGrouping.segments(
            in: group,
            splitPinnedTabs: false,
            splitOnSeparators: true
        )

        XCTAssertEqual(segments, [[1], [2, 3], [4]])
    }

    func testFocusedSegmentWindowIDsReturnsMatchingSegment() {
        let w1 = makeWindow(id: 1)
        let separator = WindowInfo.separator(withID: 9_996)
        let w2 = makeWindow(id: 2)
        let w3 = makeWindow(id: 3)
        let group = TabGroup(windows: [w1, separator, w2, w3], frame: .zero)

        let focusedIDs = TabWindowGrouping.focusedSegmentWindowIDs(
            in: group,
            focusedWindowID: w3.id,
            splitPinnedTabs: false,
            splitOnSeparators: true
        )

        XCTAssertEqual(focusedIDs, [2, 3])
    }
}
