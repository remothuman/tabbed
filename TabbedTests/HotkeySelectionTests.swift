import XCTest
@testable import Tabbed

final class HotkeySelectionTests: XCTestCase {

    private func makeWindow(id: CGWindowID) -> WindowInfo {
        WindowInfo(
            id: id,
            element: AXUIElementCreateApplication(1),
            ownerPID: 1,
            bundleID: "com.example.test",
            title: "Window \(id)",
            appName: "Test"
        )
    }

    private func makeGroup(windowIDs: [CGWindowID]) -> TabGroup {
        let windows = windowIDs.map(makeWindow)
        return TabGroup(windows: windows, frame: .zero)
    }

    func testMultiSelectedTabIDsForHotkeyReturnsNilWithoutSelection() {
        let appDelegate = AppDelegate()
        let group = makeGroup(windowIDs: [1, 2, 3])

        let ids = appDelegate.multiSelectedTabIDsForHotkey(in: group)

        XCTAssertNil(ids)
    }

    func testMultiSelectedTabIDsForHotkeyReturnsNilForSingleSelection() {
        let appDelegate = AppDelegate()
        let group = makeGroup(windowIDs: [1, 2, 3])
        appDelegate.selectedTabIDsByGroupID[group.id] = [2]

        let ids = appDelegate.multiSelectedTabIDsForHotkey(in: group)

        XCTAssertNil(ids)
    }

    func testMultiSelectedTabIDsForHotkeyReturnsSelectionWhenMultipleTabsSelected() {
        let appDelegate = AppDelegate()
        let group = makeGroup(windowIDs: [1, 2, 3])
        appDelegate.selectedTabIDsByGroupID[group.id] = [1, 3]

        let ids = appDelegate.multiSelectedTabIDsForHotkey(in: group)

        XCTAssertEqual(ids, Set([1, 3]))
    }

    func testMultiSelectedTabIDsForHotkeyPrunesStaleIDsAndReturnsNilWhenOnlyOneValidRemains() {
        let appDelegate = AppDelegate()
        let group = makeGroup(windowIDs: [10, 20])
        appDelegate.selectedTabIDsByGroupID[group.id] = [20, 999]

        let ids = appDelegate.multiSelectedTabIDsForHotkey(in: group)

        XCTAssertNil(ids)
        XCTAssertEqual(appDelegate.selectedTabIDsByGroupID[group.id], Set([20]))
    }

    func testMultiSelectedTabIDsForHotkeyPrunesStaleIDsAndReturnsValidMultiSelection() {
        let appDelegate = AppDelegate()
        let group = makeGroup(windowIDs: [10, 20, 30])
        appDelegate.selectedTabIDsByGroupID[group.id] = [10, 20, 999]

        let ids = appDelegate.multiSelectedTabIDsForHotkey(in: group)

        XCTAssertEqual(ids, Set([10, 20]))
        XCTAssertEqual(appDelegate.selectedTabIDsByGroupID[group.id], Set([10, 20]))
    }
}
