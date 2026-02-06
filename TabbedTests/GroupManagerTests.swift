import XCTest
@testable import Tabbed
import ApplicationServices

final class GroupManagerTests: XCTestCase {
    var gm: GroupManager!

    func makeWindow(id: CGWindowID) -> WindowInfo {
        let element = AXUIElementCreateSystemWide()
        return WindowInfo(
            id: id, element: element, ownerPID: 0,
            bundleID: "com.test", title: "Window \(id)",
            appName: "Test", icon: nil
        )
    }

    override func setUp() {
        gm = GroupManager()
    }

    func testCreateGroup() {
        let windows = [makeWindow(id: 1), makeWindow(id: 2)]
        let group = gm.createGroup(with: windows, frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertNotNil(group)
        XCTAssertEqual(gm.groups.count, 1)
        XCTAssertEqual(group?.windows.count, 2)
    }

    func testCreateGroupRequiresAtLeastTwoWindows() {
        let group = gm.createGroup(with: [makeWindow(id: 1)], frame: .zero)
        XCTAssertNil(group)
        XCTAssertEqual(gm.groups.count, 0)
    }

    func testCannotAddWindowAlreadyInGroup() {
        let w1 = makeWindow(id: 1)
        let w2 = makeWindow(id: 2)
        let w3 = makeWindow(id: 3)
        let group = gm.createGroup(with: [w1, w2], frame: .zero)!
        gm.addWindow(w1, to: group)
        XCTAssertEqual(group.windows.count, 2)

        // Can't create a new group containing w1 either
        let group2 = gm.createGroup(with: [w1, w3], frame: .zero)
        XCTAssertNil(group2)
    }

    func testFindGroupForWindow() {
        let windows = [makeWindow(id: 1), makeWindow(id: 2)]
        gm.createGroup(with: windows, frame: .zero)
        XCTAssertNotNil(gm.group(for: 1))
        XCTAssertNil(gm.group(for: 99))
    }

    func testRemoveWindowDissolvesGroupWhenOneLeft() {
        let windows = [makeWindow(id: 1), makeWindow(id: 2)]
        let group = gm.createGroup(with: windows, frame: .zero)!
        gm.releaseWindow(withID: 1, from: group)
        XCTAssertEqual(gm.groups.count, 0)
    }

    func testRemoveWindowKeepsGroupWithMultiple() {
        let windows = [makeWindow(id: 1), makeWindow(id: 2), makeWindow(id: 3)]
        let group = gm.createGroup(with: windows, frame: .zero)!
        gm.releaseWindow(withID: 1, from: group)
        XCTAssertEqual(gm.groups.count, 1)
        XCTAssertEqual(group.windows.count, 2)
    }

    func testIsWindowGrouped() {
        let windows = [makeWindow(id: 1), makeWindow(id: 2)]
        gm.createGroup(with: windows, frame: .zero)
        XCTAssertTrue(gm.isWindowGrouped(1))
        XCTAssertFalse(gm.isWindowGrouped(99))
    }

    func testDissolveGroup() {
        let windows = [makeWindow(id: 1), makeWindow(id: 2)]
        let group = gm.createGroup(with: windows, frame: .zero)!
        gm.dissolveGroup(group)
        XCTAssertEqual(gm.groups.count, 0)
    }
}
