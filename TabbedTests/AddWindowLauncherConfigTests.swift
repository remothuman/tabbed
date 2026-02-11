import XCTest
@testable import Tabbed

final class AddWindowLauncherConfigTests: XCTestCase {
    private var savedConfigData: Data?

    override func setUp() {
        super.setUp()
        savedConfigData = UserDefaults.standard.data(forKey: "addWindowLauncherConfig")
        UserDefaults.standard.removeObject(forKey: "addWindowLauncherConfig")
    }

    override func tearDown() {
        if let data = savedConfigData {
            UserDefaults.standard.set(data, forKey: "addWindowLauncherConfig")
        } else {
            UserDefaults.standard.removeObject(forKey: "addWindowLauncherConfig")
        }
        super.tearDown()
    }

    func testDefaults() {
        let config = AddWindowLauncherConfig.default
        XCTAssertTrue(config.urlLaunchEnabled)
        XCTAssertEqual(config.providerMode, .auto)
        XCTAssertEqual(config.searchEngine, .google)
        XCTAssertEqual(config.manualSelection.engine, .chromium)
        XCTAssertEqual(config.manualSelection.bundleID, "")
    }

    func testSaveLoadRoundTrip() {
        let config = AddWindowLauncherConfig(
            urlLaunchEnabled: false,
            providerMode: .manual,
            searchEngine: .bing,
            manualSelection: BrowserProviderSelection(bundleID: "org.mozilla.firefox", engine: .firefox)
        )

        config.save()
        let loaded = AddWindowLauncherConfig.load()

        XCTAssertEqual(loaded, config)
    }

    func testBackwardCompatibleDecodeWithMissingKeys() throws {
        let json = "{}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AddWindowLauncherConfig.self, from: json)
        XCTAssertEqual(decoded, .default)
    }
}
