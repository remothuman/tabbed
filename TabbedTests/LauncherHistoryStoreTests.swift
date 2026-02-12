import XCTest
@testable import Tabbed

final class LauncherHistoryStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var now: Date!
    private let storageKey = "test.launcher.history"

    override func setUp() {
        super.setUp()
        suiteName = "LauncherHistoryStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        now = Date(timeIntervalSince1970: 1_700_000_000)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        now = nil
        super.tearDown()
    }

    private func makeStore() -> LauncherHistoryStore {
        LauncherHistoryStore(
            userDefaults: defaults,
            storageKey: storageKey,
            nowProvider: { [weak self] in self?.now ?? Date() },
            urlLimit: 300,
            appLimit: 200
        )
    }

    func testRoundTripPersistsURLAndAppEntries() {
        let store = makeStore()

        store.recordURLLaunch(URL(string: "https://example.com")!, outcome: .succeeded)
        now = now.addingTimeInterval(30)
        store.recordAppLaunch(bundleID: "com.example.app", outcome: .timedOut(status: "No new window detected"))
        now = now.addingTimeInterval(30)
        store.recordActionUsage(actionID: "action.closeAllWindowsInTargetGroup", outcome: .succeeded)

        let reloaded = makeStore()
        let urls = reloaded.urlEntries()
        let apps = reloaded.appEntriesByBundleID()
        let actions = reloaded.actionEntriesByID()

        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls[0].urlString, "https://example.com")
        XCTAssertEqual(urls[0].launchCount, 1)

        XCTAssertEqual(apps["com.example.app"]?.launchCount, 1)
        XCTAssertEqual(apps["com.example.app"]?.bundleID, "com.example.app")
        XCTAssertEqual(actions["action.closeAllWindowsInTargetGroup"]?.launchCount, 1)
        XCTAssertEqual(actions["action.closeAllWindowsInTargetGroup"]?.actionID, "action.closeAllWindowsInTargetGroup")
    }

    func testFailedOutcomesAreNotRecorded() {
        let store = makeStore()

        store.recordURLLaunch(URL(string: "https://example.com")!, outcome: .failed(status: "Unable to open URL"))
        store.recordAppLaunch(bundleID: "com.example.app", outcome: .failed(status: "Unable to launch app"))
        store.recordActionUsage(actionID: "action.renameTargetGroup", outcome: .failed(status: "Action failed"))

        XCTAssertTrue(store.urlEntries().isEmpty)
        XCTAssertTrue(store.appEntriesByBundleID().isEmpty)
        XCTAssertTrue(store.actionEntriesByID().isEmpty)
    }

    func testFrequencyAndRecencyAffectURLOrdering() {
        let store = makeStore()

        store.recordURLLaunch(URL(string: "https://alpha.com")!, outcome: .succeeded)
        now = now.addingTimeInterval(10)
        store.recordURLLaunch(URL(string: "https://bravo.com")!, outcome: .succeeded)
        now = now.addingTimeInterval(10)
        store.recordURLLaunch(URL(string: "https://alpha.com")!, outcome: .succeeded)

        let urls = store.urlEntries()
        XCTAssertEqual(urls.map(\.urlString), ["https://alpha.com", "https://bravo.com"])
        XCTAssertEqual(urls[0].launchCount, 2)
        XCTAssertEqual(urls[1].launchCount, 1)
    }

    func testSearchURLsAreExcludedFromHistory() {
        let store = makeStore()

        store.recordURLLaunch(URL(string: "https://www.google.com/search?q=tabbed")!, outcome: .succeeded)
        store.recordURLLaunch(URL(string: "https://duckduckgo.com/?q=tabbed")!, outcome: .timedOut(status: "No new window detected"))
        store.recordURLLaunch(URL(string: "https://example.com/docs")!, outcome: .succeeded)

        let urls = store.urlEntries()
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls[0].urlString, "https://example.com/docs")
    }

    func testCanonicalURLDeduplicatesHostCase() {
        let store = makeStore()

        store.recordURLLaunch(URL(string: "HTTPS://EXAMPLE.COM/path")!, outcome: .succeeded)
        now = now.addingTimeInterval(10)
        store.recordURLLaunch(URL(string: "https://example.com/path")!, outcome: .succeeded)

        let urls = store.urlEntries()
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls[0].urlString, "https://example.com/path")
        XCTAssertEqual(urls[0].launchCount, 2)
    }

    func testRecordingURLPostsUpdateNotification() {
        let store = makeStore()
        let expectation = expectation(description: "History update notification")

        let observer = NotificationCenter.default.addObserver(
            forName: LauncherHistoryStore.didUpdateNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard let key = notification.userInfo?[LauncherHistoryStore.storageKeyUserInfoKey] as? String,
                  key == self.storageKey else { return }
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        store.recordURLLaunch(URL(string: "https://example.com")!, outcome: .succeeded)
        wait(for: [expectation], timeout: 1.0)
    }

    func testActionUsageAggregatesCountAndRecency() {
        let store = makeStore()

        store.recordActionUsage(actionID: "action.ungroupTargetGroup", outcome: .succeeded)
        now = now.addingTimeInterval(10)
        store.recordActionUsage(actionID: "action.closeAllWindowsInTargetGroup", outcome: .succeeded)
        now = now.addingTimeInterval(10)
        store.recordActionUsage(actionID: "action.ungroupTargetGroup", outcome: .timedOut(status: "No-op"))

        let actions = store.actionEntriesByID()
        XCTAssertEqual(actions["action.ungroupTargetGroup"]?.launchCount, 2)
        XCTAssertEqual(actions["action.closeAllWindowsInTargetGroup"]?.launchCount, 1)

        guard let ungroupDate = actions["action.ungroupTargetGroup"]?.lastLaunchedAt,
              let closeDate = actions["action.closeAllWindowsInTargetGroup"]?.lastLaunchedAt else {
            return XCTFail("Expected both action entries to exist")
        }
        XCTAssertGreaterThan(ungroupDate, closeDate)
    }
}
