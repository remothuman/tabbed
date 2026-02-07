import XCTest
@testable import Tabbed

final class SwitcherItemBuilderTests: XCTestCase {

    private func makeWindow(id: CGWindowID, appName: String = "App", title: String = "") -> WindowInfo {
        let element = AXUIElementCreateSystemWide()
        return WindowInfo(id: id, element: element, ownerPID: 1, bundleID: "com.test", title: title, appName: appName, icon: nil)
    }

    func testUngroupedWindowsPreserveZOrder() {
        let w1 = makeWindow(id: 1, appName: "A")
        let w2 = makeWindow(id: 2, appName: "B")
        let w3 = makeWindow(id: 3, appName: "C")

        let items = SwitcherItemBuilder.build(zOrderedWindows: [w1, w2, w3], groups: [])

        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].windowIDs, [1])
        XCTAssertEqual(items[1].windowIDs, [2])
        XCTAssertEqual(items[2].windowIDs, [3])
    }

    func testGroupCoalescedAtFrontmostPosition() {
        // z-order: w1(ungrouped), w2(in group), w3(ungrouped), w4(in group)
        let w1 = makeWindow(id: 1)
        let w2 = makeWindow(id: 2)
        let w3 = makeWindow(id: 3)
        let w4 = makeWindow(id: 4)

        let group = TabGroup(windows: [w2, w4], frame: .zero)

        let items = SwitcherItemBuilder.build(zOrderedWindows: [w1, w2, w3, w4], groups: [group])

        // Expected: w1, group(w2+w4), w3
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].windowIDs, [1])
        XCTAssertTrue(items[1].isGroup)
        XCTAssertEqual(items[1].windowCount, 2)
        XCTAssertEqual(items[2].windowIDs, [3])
    }

    func testEmptyInput() {
        let items = SwitcherItemBuilder.build(zOrderedWindows: [], groups: [])
        XCTAssertTrue(items.isEmpty)
    }

    func testMultipleGroups() {
        let w1 = makeWindow(id: 1)
        let w2 = makeWindow(id: 2)
        let w3 = makeWindow(id: 3)
        let w4 = makeWindow(id: 4)

        let groupA = TabGroup(windows: [w1, w3], frame: .zero)
        let groupB = TabGroup(windows: [w2, w4], frame: .zero)

        let items = SwitcherItemBuilder.build(zOrderedWindows: [w1, w2, w3, w4], groups: [groupA, groupB])

        // w1 is first in z-order and in groupA -> groupA appears at position 0
        // w2 is next and in groupB -> groupB appears at position 1
        // w3 and w4 are already claimed by their groups
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items[0].isGroup)
        XCTAssertTrue(items[1].isGroup)
    }
}
