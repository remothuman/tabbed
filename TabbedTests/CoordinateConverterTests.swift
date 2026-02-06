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

    func testVisibleFrameInAXReturnsNonZero() {
        let frame = CoordinateConverter.visibleFrameInAX()
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
    }
}
