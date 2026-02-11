import XCTest
@testable import Tabbed

final class URLNormalizationTests: XCTestCase {

    func testSchemeLessHostGetsHTTPSPrepended() {
        let url = LauncherEngine.normalizeURL(from: "example.com/path")
        XCTAssertEqual(url?.absoluteString, "https://example.com/path")
    }

    func testLocalhostIPv4AndIPv6AreAccepted() {
        XCTAssertEqual(LauncherEngine.normalizeURL(from: "localhost:3000")?.absoluteString, "https://localhost:3000")
        XCTAssertEqual(LauncherEngine.normalizeURL(from: "127.0.0.1:8080")?.absoluteString, "https://127.0.0.1:8080")
        XCTAssertEqual(LauncherEngine.normalizeURL(from: "[::1]:8080")?.absoluteString, "https://[::1]:8080")
    }

    func testInvalidInputRejected() {
        XCTAssertNil(LauncherEngine.normalizeURL(from: "not-a-url"))
        XCTAssertNil(LauncherEngine.normalizeURL(from: "http://bad host"))
        XCTAssertNil(LauncherEngine.normalizeURL(from: ""))
    }

    func testSearchFallbackURLGeneration() {
        XCTAssertEqual(
            SearchEngine.google.searchURL(for: "alpha beta")?.absoluteString,
            "https://www.google.com/search?q=alpha%20beta"
        )
        XCTAssertEqual(
            SearchEngine.duckDuckGo.searchURL(for: "alpha")?.absoluteString,
            "https://duckduckgo.com/?q=alpha"
        )
        XCTAssertEqual(
            SearchEngine.bing.searchURL(for: "alpha")?.absoluteString,
            "https://www.bing.com/search?q=alpha"
        )
        XCTAssertNil(SearchEngine.providerNative.searchURL(for: "alpha"))
    }
}
