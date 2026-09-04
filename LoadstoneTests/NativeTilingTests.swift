import XCTest
@testable import Loadstone

final class NativeTilingTests: XCTestCase {
    private let edge = "EnableTilingByEdgeDrag"
    private let top = "EnableTopTilingByEdgeDrag"

    private func scratchDefaults() -> UserDefaults {
        let name = "com.brudvik.loadstone.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return defaults
    }

    func testDisablingTurnsBothKeysOff() {
        let defaults = scratchDefaults()
        let tiling = NativeTiling(defaults: defaults)

        tiling.disableEdgeTiling()

        XCTAssertEqual(defaults.object(forKey: edge) as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: top) as? Bool, false)
    }

    func testRestoringRemovesKeysThatWereAbsentBefore() {
        let defaults = scratchDefaults()
        let tiling = NativeTiling(defaults: defaults)
        tiling.disableEdgeTiling()

        tiling.restoreEdgeTiling()

        XCTAssertNil(defaults.object(forKey: edge), "macOS's own default must apply again")
        XCTAssertNil(defaults.object(forKey: top))
    }

    func testRestoringPutsBackValuesTheUserHadSet() {
        let defaults = scratchDefaults()
        defaults.set(true, forKey: edge)
        defaults.set(false, forKey: top)
        let tiling = NativeTiling(defaults: defaults)
        tiling.disableEdgeTiling()

        tiling.restoreEdgeTiling()

        XCTAssertEqual(defaults.object(forKey: edge) as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: top) as? Bool, false)
    }

    func testDisablingTwiceKeepsTheOriginalValues() {
        let defaults = scratchDefaults()
        defaults.set(true, forKey: edge)
        let tiling = NativeTiling(defaults: defaults)

        tiling.disableEdgeTiling()
        tiling.disableEdgeTiling()
        tiling.restoreEdgeTiling()

        XCTAssertEqual(defaults.object(forKey: edge) as? Bool, true)
        XCTAssertNil(defaults.object(forKey: top))
    }

    func testRestoringWithoutDisablingChangesNothing() {
        let defaults = scratchDefaults()
        defaults.set(false, forKey: edge)

        NativeTiling(defaults: defaults).restoreEdgeTiling()

        XCTAssertEqual(defaults.object(forKey: edge) as? Bool, false)
    }
}
