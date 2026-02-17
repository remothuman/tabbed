import XCTest
@testable import Tabbed

final class AddWindowMRUTests: XCTestCase {
    private func makeWindow(id: CGWindowID) -> WindowInfo {
        WindowInfo(
            id: id,
            element: AXUIElementCreateSystemWide(),
            ownerPID: 1,
            bundleID: "com.test",
            title: "Window \(id)",
            appName: "Test"
        )
    }

    func testAddWindowPromotesNewlyActivatedWindowToMRUFront() {
        let app = AppDelegate()
        let first = makeWindow(id: 1)
        let second = makeWindow(id: 2)
        guard let group = app.groupManager.createGroup(with: [first, second], frame: .zero) else {
            XCTFail("Expected group creation")
            return
        }

        let newlyAdded = makeWindow(id: 3)
        app.addWindow(newlyAdded, to: group, afterActive: true)

        XCTAssertEqual(group.activeWindow?.id, newlyAdded.id)
        XCTAssertEqual(group.focusHistory.first, newlyAdded.id)
    }
}
