import XCTest
@testable import Tabbed

final class CoordinateConverterTests: XCTestCase {
    func testAXToAppKitRoundTrip() {
        let original = CGPoint(x: 100, y: 200)
        let windowHeight: CGFloat = 400
        let appKit = CoordinateConverter.axToAppKit(point: original, windowHeight: windowHeight)
        let backToAX = CoordinateConverter.appKitToAX(point: appKit, windowHeight: windowHeight)
        XCTAssertEqual(original.x, backToAX.x, accuracy: 0.01)
        XCTAssertEqual(original.y, backToAX.y, accuracy: 0.01)
    }

    func testRoundTripWithLargeCoordinates() {
        // Simulates a point on a secondary monitor to the right
        let original = CGPoint(x: 2000, y: 100)
        let windowHeight: CGFloat = 600
        let appKit = CoordinateConverter.axToAppKit(point: original, windowHeight: windowHeight)
        let backToAX = CoordinateConverter.appKitToAX(point: appKit, windowHeight: windowHeight)
        XCTAssertEqual(original.x, backToAX.x, accuracy: 0.01)
        XCTAssertEqual(original.y, backToAX.y, accuracy: 0.01)
    }

    func testVisibleFrameInAXReturnsNonZero() {
        // Use a point on the primary screen
        let frame = CoordinateConverter.visibleFrameInAX(at: CGPoint(x: 100, y: 100))
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
    }

    func testVisibleFrameForScreenReturnsNonZero() {
        guard let screen = NSScreen.screens.first else { return }
        let frame = CoordinateConverter.visibleFrameInAX(for: screen)
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
    }

    func testScreenContainingPrimaryOrigin() {
        // Top-left of primary screen in AX coords is (0, 0)
        let screen = CoordinateConverter.screen(containingAXPoint: CGPoint(x: 10, y: 10))
        XCTAssertNotNil(screen)
        // Should be the primary screen
        XCTAssertEqual(screen, NSScreen.screens.first)
    }
}
