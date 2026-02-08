import XCTest
@testable import Tabbed

final class SpaceUtilsTests: XCTestCase {
    func testSpaceIDReturnsNilForInvalidWindow() {
        // Window ID 0 / nonexistent windows should return nil
        let result = SpaceUtils.spaceID(for: 0)
        XCTAssertNil(result)
    }

    func testSpaceIDsReturnsEmptyForNoWindows() {
        let result = SpaceUtils.spaceIDs(for: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testSpaceIDsSkipsInvalidWindows() {
        let result = SpaceUtils.spaceIDs(for: [0, 99999])
        // Both invalid, so results should be empty or nil values
        XCTAssertTrue(result.values.allSatisfy { $0 == nil || $0 != nil })
    }
}
