import XCTest
@testable import Tabbed

final class SwitcherConfigTests: XCTestCase {
    private let key = "switcherConfig"
    private var savedData: Data?

    override func setUp() {
        super.setUp()
        savedData = UserDefaults.standard.data(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
    }

    override func tearDown() {
        if let savedData {
            UserDefaults.standard.set(savedData, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    func testDefaultNamedGroupLabelMode() {
        let config = SwitcherConfig()
        XCTAssertEqual(config.namedGroupLabelMode, .groupAppWindow)
    }

    func testDecodeLegacyStyleUsesDefaultNamedGroupLabelMode() throws {
        let legacyJSON = #"{"style":"titles"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SwitcherConfig.self, from: legacyJSON)
        XCTAssertEqual(decoded.globalStyle, .titles)
        XCTAssertEqual(decoded.tabCycleStyle, .titles)
        XCTAssertEqual(decoded.namedGroupLabelMode, .groupAppWindow)
    }

    func testDecodeModernWithoutNamedGroupLabelModeUsesDefault() throws {
        let modernJSON = #"{"globalStyle":"appIcons","tabCycleStyle":"titles"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SwitcherConfig.self, from: modernJSON)
        XCTAssertEqual(decoded.globalStyle, .appIcons)
        XCTAssertEqual(decoded.tabCycleStyle, .titles)
        XCTAssertEqual(decoded.namedGroupLabelMode, .groupAppWindow)
    }

    func testSaveAndLoadNamedGroupLabelMode() {
        var config = SwitcherConfig()
        config.namedGroupLabelMode = .groupNameOnly
        config.save()

        let loaded = SwitcherConfig.load()
        XCTAssertEqual(loaded.namedGroupLabelMode, .groupNameOnly)
    }
}
