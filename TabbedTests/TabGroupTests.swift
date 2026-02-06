import XCTest
@testable import Tabbed
import ApplicationServices

final class TabGroupTests: XCTestCase {
    func makeWindow(id: CGWindowID) -> WindowInfo {
        let element = AXUIElementCreateSystemWide()
        return WindowInfo(
            id: id,
            element: element,
            ownerPID: 0,
            bundleID: "com.test",
            title: "Window \(id)",
            appName: "Test",
            icon: nil
        )
    }

    func testInitSetsActiveIndexToZero() {
        let group = TabGroup(windows: [makeWindow(id: 1), makeWindow(id: 2)], frame: .zero)
        XCTAssertEqual(group.activeIndex, 0)
    }

    func testActiveWindow() {
        let w1 = makeWindow(id: 1)
        let w2 = makeWindow(id: 2)
        let group = TabGroup(windows: [w1, w2], frame: .zero)
        XCTAssertEqual(group.activeWindow?.id, 1)
        group.switchTo(index: 1)
        XCTAssertEqual(group.activeWindow?.id, 2)
    }

    func testContains() {
        let group = TabGroup(windows: [makeWindow(id: 1)], frame: .zero)
        XCTAssertTrue(group.contains(windowID: 1))
        XCTAssertFalse(group.contains(windowID: 99))
    }

    func testAddWindow() {
        let group = TabGroup(windows: [makeWindow(id: 1)], frame: .zero)
        group.addWindow(makeWindow(id: 2))
        XCTAssertEqual(group.windows.count, 2)
    }

    func testAddDuplicateWindowIsIgnored() {
        let group = TabGroup(windows: [makeWindow(id: 1)], frame: .zero)
        group.addWindow(makeWindow(id: 1))
        XCTAssertEqual(group.windows.count, 1)
    }

    func testRemoveWindow() {
        let group = TabGroup(windows: [makeWindow(id: 1), makeWindow(id: 2)], frame: .zero)
        let removed = group.removeWindow(withID: 1)
        XCTAssertEqual(removed?.id, 1)
        XCTAssertEqual(group.windows.count, 1)
    }

    func testRemoveActiveWindowAdjustsIndex() {
        let group = TabGroup(windows: [makeWindow(id: 1), makeWindow(id: 2)], frame: .zero)
        group.switchTo(index: 1)
        group.removeWindow(at: 1)
        XCTAssertEqual(group.activeIndex, 0)
    }

    func testRemoveWindowBeforeActiveAdjustsIndex() {
        let group = TabGroup(windows: [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3), makeWindow(id: 4)], frame: .zero)
        group.switchTo(index: 2) // Window 3 is active
        group.removeWindow(at: 0) // Remove Window 1
        XCTAssertEqual(group.activeIndex, 1)
        XCTAssertEqual(group.activeWindow?.id, 3)
    }

    func testSwitchToIndex() {
        let group = TabGroup(windows: [makeWindow(id: 1), makeWindow(id: 2)], frame: .zero)
        group.switchTo(index: 1)
        XCTAssertEqual(group.activeIndex, 1)
    }

    func testSwitchToInvalidIndexDoesNothing() {
        let group = TabGroup(windows: [makeWindow(id: 1)], frame: .zero)
        group.switchTo(index: 5)
        XCTAssertEqual(group.activeIndex, 0)
    }

    func testSwitchToWindowID() {
        let group = TabGroup(windows: [makeWindow(id: 1), makeWindow(id: 2)], frame: .zero)
        group.switchTo(windowID: 2)
        XCTAssertEqual(group.activeIndex, 1)
    }

    func testMoveTab() {
        let group = TabGroup(windows: [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)], frame: .zero)
        group.moveTab(from: 0, to: 2)
        XCTAssertEqual(group.windows.map(\.id), [2, 1, 3])
    }

    func testMoveTabUpdatesActiveIndex() {
        let group = TabGroup(windows: [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)], frame: .zero)
        group.switchTo(index: 0)
        group.moveTab(from: 0, to: 2)
        XCTAssertEqual(group.activeIndex, 1)
        XCTAssertEqual(group.activeWindow?.id, 1)
    }
}
