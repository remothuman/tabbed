import XCTest
@testable import Tabbed
import ApplicationServices

final class LaunchOrchestratorTests: XCTestCase {

    private func makeWindow(id: CGWindowID, pid: pid_t) -> WindowInfo {
        WindowInfo(
            id: id,
            element: AXUIElementCreateSystemWide(),
            ownerPID: pid,
            bundleID: "com.test.app",
            title: "W\(id)",
            appName: "Test",
            icon: nil
        )
    }

    private func makeApp(isRunning: Bool) -> AppCatalogService.AppRecord {
        AppCatalogService.AppRecord(
            bundleID: "com.test.app",
            displayName: "Test App",
            appURL: URL(fileURLWithPath: "/Applications/Test.app"),
            icon: nil,
            isRunning: isRunning,
            runningPID: isRunning ? 42 : nil,
            recency: 10
        )
    }

    func testRunningAppAttemptsNewWindowBeforeReopenAndActivation() {
        var callOrder: [String] = []

        var deps = LaunchOrchestrator.Dependencies()
        deps.listWindows = { [self.makeWindow(id: 1, pid: 42)] }
        deps.runningPIDForBundle = { _ in 42 }
        deps.attemptProviderNewWindow = { _ in
            callOrder.append("provider")
            return false
        }
        deps.reopenRunningApp = { _, _ in
            callOrder.append("reopen")
            return true
        }
        deps.activateApp = { _ in
            callOrder.append("activate")
        }
        deps.sleep = { _ in }

        let orchestrator = LaunchOrchestrator(
            timing: .init(timeout: 0, pollInterval: 0),
            dependencies: deps
        )

        let outcome = orchestrator.launchAppAndCaptureSync(
            app: makeApp(isRunning: true),
            request: .init(mode: .newGroup, currentSpaceID: 1)
        )

        XCTAssertEqual(callOrder, ["provider", "reopen", "activate"])
        XCTAssertEqual(outcome.result, .timedOut(status: "No new window detected"))
    }

    func testTimeoutFallsBackToActivation() {
        var didActivate = false
        var reopenCalls = 0

        var deps = LaunchOrchestrator.Dependencies()
        deps.listWindows = { [self.makeWindow(id: 1, pid: 42)] }
        deps.runningPIDForBundle = { _ in 42 }
        deps.attemptProviderNewWindow = { _ in true }
        deps.reopenRunningApp = { _, _ in
            reopenCalls += 1
            return true
        }
        deps.activateApp = { _ in
            didActivate = true
        }
        deps.sleep = { _ in }

        let orchestrator = LaunchOrchestrator(
            timing: .init(timeout: 0, pollInterval: 0),
            dependencies: deps
        )

        let outcome = orchestrator.launchAppAndCaptureSync(
            app: makeApp(isRunning: true),
            request: .init(mode: .newGroup, currentSpaceID: 1)
        )

        XCTAssertEqual(reopenCalls, 1)
        XCTAssertTrue(didActivate)
        XCTAssertEqual(outcome.result, .timedOut(status: "No new window detected"))
    }

    func testCaptureReturnsFirstEligibleNewWindow() {
        var pollCount = 0

        var deps = LaunchOrchestrator.Dependencies()
        deps.launchApplication = { _, _ in true }
        deps.runningPIDForBundle = { _ in 52 }
        deps.isWindowGrouped = { _ in false }
        deps.spaceIDForWindow = { _ in 7 }
        deps.listWindows = {
            defer { pollCount += 1 }
            if pollCount == 0 {
                return [self.makeWindow(id: 1, pid: 52)]
            }
            return [self.makeWindow(id: 1, pid: 52), self.makeWindow(id: 2, pid: 52)]
        }
        deps.sleep = { _ in }

        let orchestrator = LaunchOrchestrator(
            timing: .init(timeout: 0.01, pollInterval: 0),
            dependencies: deps
        )

        let outcome = orchestrator.launchAppAndCaptureSync(
            app: makeApp(isRunning: false),
            request: .init(mode: .newGroup, currentSpaceID: 7)
        )

        XCTAssertEqual(outcome.result, .succeeded)
        XCTAssertEqual(outcome.capturedWindow?.id, 2)
    }
}
