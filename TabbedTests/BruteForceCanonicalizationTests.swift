import XCTest
import CoreGraphics
@testable import Tabbed

final class BruteForceCanonicalizationTests: XCTestCase {

    private struct MockElement: Hashable {
        let id: Int
    }

    func testCanonicalizeDiscoveredElementPromotesContainerWhenWindowIDMatches() {
        let child = MockElement(id: 1)
        let container = MockElement(id: 2)

        let normalized = canonicalizeDiscoveredElement(
            child,
            expectedWindowID: 42,
            windowAttribute: { element in
                element == child ? container : nil
            },
            windowID: { element in
                element == container ? 42 : 7
            }
        )

        XCTAssertEqual(normalized, container)
    }

    func testCanonicalizeDiscoveredElementKeepsOriginalWhenWindowIDDiffers() {
        let child = MockElement(id: 1)
        let container = MockElement(id: 2)

        let normalized = canonicalizeDiscoveredElement(
            child,
            expectedWindowID: 42,
            windowAttribute: { element in
                element == child ? container : nil
            },
            windowID: { element in
                element == container ? 99 : 7
            }
        )

        XCTAssertEqual(normalized, child)
    }

    func testCanonicalizeDiscoveredElementKeepsOriginalWhenContainerMissing() {
        let child = MockElement(id: 1)

        let normalized = canonicalizeDiscoveredElement(
            child,
            expectedWindowID: 42,
            windowAttribute: { _ in nil },
            windowID: { _ in nil }
        )

        XCTAssertEqual(normalized, child)
    }
}
