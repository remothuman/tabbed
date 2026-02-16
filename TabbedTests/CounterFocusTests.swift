import XCTest
@testable import Tabbed

final class CounterFocusTests: XCTestCase {
    private final class SpyTabBarPanel: TabBarPanel {
        var showCallCount = 0
        var lastShowFrame: CGRect?
        var lastShowWindowID: CGWindowID?
        var lastShowMaximized: Bool?
        var orderFrontRegardlessCallCount = 0
        var orderCalls: [(mode: Int, relativeTo: Int)] = []
        var orderOutCallCount = 0

        override func show(above windowFrame: CGRect, windowID: CGWindowID, isMaximized: Bool = false) {
            showCallCount += 1
            lastShowFrame = windowFrame
            lastShowWindowID = windowID
            lastShowMaximized = isMaximized
        }

        override func orderFrontRegardless() {
            orderFrontRegardlessCallCount += 1
        }

        override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
            orderCalls.append((mode: place.rawValue, relativeTo: otherWin))
        }

        override func orderOut(_ sender: Any?) {
            orderOutCallCount += 1
        }
    }

    private func makeWindow(id: CGWindowID, isFullscreened: Bool = false) -> WindowInfo {
        WindowInfo(
            id: id,
            element: AXUIElementCreateSystemWide(),
            ownerPID: 1,
            bundleID: "com.test",
            title: "Window \(id)",
            appName: "Test",
            isFullscreened: isFullscreened
        )
    }

    func testPerformCounterFocusShowsTargetPanelEvenWhenWindowAlreadyFocused() {
        let app = AppDelegate()
        let window = makeWindow(id: 101)
        guard let group = app.groupManager.createGroup(with: [window], frame: CGRect(x: 50, y: 80, width: 900, height: 650)) else {
            XCTFail("Expected group creation")
            return
        }
        let panel = SpyTabBarPanel()
        app.tabBarPanels[group.id] = panel

        app.performCounterFocus(on: group, activeWindow: window, focusedWindowID: window.id)

        XCTAssertEqual(panel.showCallCount, 1)
        XCTAssertEqual(panel.lastShowWindowID, window.id)
        XCTAssertEqual(panel.lastShowFrame, group.frame)
    }

    func testPerformCounterFocusSkipsPanelShowForFullscreenWindow() {
        let app = AppDelegate()
        let fullscreenWindow = makeWindow(id: 202, isFullscreened: true)
        guard let group = app.groupManager.createGroup(with: [fullscreenWindow], frame: CGRect(x: 0, y: 0, width: 1200, height: 700)) else {
            XCTFail("Expected group creation")
            return
        }
        let panel = SpyTabBarPanel()
        app.tabBarPanels[group.id] = panel

        app.performCounterFocus(on: group, activeWindow: fullscreenWindow, focusedWindowID: fullscreenWindow.id)

        XCTAssertEqual(panel.showCallCount, 0)
    }

    func testPrioritizePanelZOrderForSharedWindowPromotesOwnerPanel() {
        let app = AppDelegate()
        let shared = makeWindow(id: 303)
        guard let groupA = app.groupManager.createGroup(with: [shared], frame: CGRect(x: 20, y: 20, width: 700, height: 500)),
              let groupB = app.groupManager.createGroup(with: [shared], frame: CGRect(x: 40, y: 40, width: 700, height: 500), allowSharedMembership: true) else {
            XCTFail("Expected shared groups")
            return
        }

        let panelA = SpyTabBarPanel()
        let panelB = SpyTabBarPanel()
        app.tabBarPanels[groupA.id] = panelA
        app.tabBarPanels[groupB.id] = panelB

        app.prioritizePanelZOrderForSharedWindow(windowID: shared.id, ownerGroupID: groupB.id)

        XCTAssertEqual(panelB.orderFrontRegardlessCallCount, 1)
        XCTAssertEqual(panelA.orderOutCallCount, 1)
        XCTAssertFalse(panelA.orderCalls.contains(where: { $0.mode == NSWindow.OrderingMode.below.rawValue }))
    }
}
