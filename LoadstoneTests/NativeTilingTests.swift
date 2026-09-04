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

    /// `NativeTiling`'s marker defaults to `UserDefaults.standard`, which under `TEST_HOST` is
    /// the real app's domain. Every test gets its own scratch marker so runs cannot leak into
    /// the user's defaults or into each other.
    private func makeTiling(_ defaults: UserDefaults) -> NativeTiling {
        NativeTiling(defaults: defaults, marker: scratchDefaults())
    }

    func testDisablingTurnsBothKeysOff() {
        let defaults = scratchDefaults()
        let tiling = makeTiling(defaults)

        tiling.disableEdgeTiling()

        XCTAssertEqual(defaults.object(forKey: edge) as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: top) as? Bool, false)
    }

    func testRestoringRemovesKeysThatWereAbsentBefore() {
        let defaults = scratchDefaults()
        let tiling = makeTiling(defaults)
        tiling.disableEdgeTiling()

        tiling.restoreEdgeTiling()

        XCTAssertNil(defaults.object(forKey: edge), "macOS's own default must apply again")
        XCTAssertNil(defaults.object(forKey: top))
    }

    func testRestoringPutsBackValuesTheUserHadSet() {
        let defaults = scratchDefaults()
        defaults.set(true, forKey: edge)
        defaults.set(false, forKey: top)
        let tiling = makeTiling(defaults)
        tiling.disableEdgeTiling()

        tiling.restoreEdgeTiling()

        XCTAssertEqual(defaults.object(forKey: edge) as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: top) as? Bool, false)
    }

    func testDisablingTwiceKeepsTheOriginalValues() {
        let defaults = scratchDefaults()
        defaults.set(true, forKey: edge)
        let tiling = makeTiling(defaults)

        tiling.disableEdgeTiling()
        tiling.disableEdgeTiling()
        tiling.restoreEdgeTiling()

        XCTAssertEqual(defaults.object(forKey: edge) as? Bool, true)
        XCTAssertNil(defaults.object(forKey: top))
    }

    func testRestoringWithoutDisablingChangesNothing() {
        let defaults = scratchDefaults()
        defaults.set(false, forKey: edge)

        makeTiling(defaults).restoreEdgeTiling()

        XCTAssertEqual(defaults.object(forKey: edge) as? Bool, false)
    }

    func testAForceQuitLeavesAMarkerTheNextLaunchRestoresFrom() {
        let system = scratchDefaults()
        let marker = scratchDefaults()
        system.set(true, forKey: edge)

        // First launch turns tiling off and is then force-quit, so restoreEdgeTiling never runs.
        NativeTiling(defaults: system, marker: marker).disableEdgeTiling()
        XCTAssertEqual(system.object(forKey: edge) as? Bool, false)

        // The next launch must recover the user's value before recording a new one, or it would
        // record Loadstone's own false as "what the user had" and make the change permanent.
        let second = NativeTiling(defaults: system, marker: marker)
        second.disableEdgeTiling()
        second.restoreEdgeTiling()

        XCTAssertEqual(system.object(forKey: edge) as? Bool, true)
    }

    func testAForceQuitDoesNotResurrectKeysTheUserNeverSet() {
        let system = scratchDefaults()
        let marker = scratchDefaults()

        NativeTiling(defaults: system, marker: marker).disableEdgeTiling()

        let second = NativeTiling(defaults: system, marker: marker)
        second.disableEdgeTiling()
        second.restoreEdgeTiling()

        XCTAssertNil(system.object(forKey: edge), "macOS's own default must apply again")
        XCTAssertNil(system.object(forKey: top))
    }

    func testACleanQuitLeavesNoMarkerBehind() {
        let system = scratchDefaults()
        let marker = scratchDefaults()
        let tiling = NativeTiling(defaults: system, marker: marker)

        tiling.disableEdgeTiling()
        XCTAssertNotNil(marker.object(forKey: NativeTiling.markerKey), "a run in progress is marked")
        tiling.restoreEdgeTiling()

        XCTAssertNil(marker.object(forKey: NativeTiling.markerKey), "a clean quit clears the marker")
    }
}
