import AppKit
import ServiceManagement
import XCTest
@testable import Loadstone

@MainActor
final class EdgeDragMonitorTests: XCTestCase {
    /// Stands in for the real NSEvent monitors, which the system only hands out to a process
    /// trusted for Accessibility.
    private final class FakeMonitors: MouseEventMonitoring {
        var installs = 0
        var uninstalls = 0
        var isInstalled = false
        /// What the system answers: false models a machine without Accessibility trust.
        var succeeds = true

        @discardableResult
        func install(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> Void) -> Bool {
            installs += 1
            isInstalled = succeeds
            return succeeds
        }

        func uninstall() {
            uninstalls += 1
            isInstalled = false
        }
    }

    private func makeSettings(dragSnapping: Bool) -> AppSettings {
        let name = "com.brudvik.loadstone.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(dragSnapping, forKey: "dragSnappingEnabled")
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return AppSettings(defaults: defaults, loginItems: NeverRegisteringLoginItems())
    }

    func testStartingWithSnappingOnInstallsTheMonitors() {
        let monitors = FakeMonitors()
        let monitor = EdgeDragMonitor(settings: makeSettings(dragSnapping: true), monitors: monitors)

        monitor.start()

        XCTAssertEqual(monitors.installs, 1)
        XCTAssertTrue(monitor.isMonitoring)
    }

    func testStartingWithSnappingOffInstallsNothing() {
        let monitors = FakeMonitors()
        let monitor = EdgeDragMonitor(settings: makeSettings(dragSnapping: false), monitors: monitors)

        monitor.start()

        XCTAssertEqual(monitors.installs, 0)
        XCTAssertFalse(monitor.isMonitoring)
    }

    func testTurningTheSettingOffUninstallsAndBackOnReinstalls() {
        let monitors = FakeMonitors()
        let settings = makeSettings(dragSnapping: true)
        let monitor = EdgeDragMonitor(settings: settings, monitors: monitors)
        monitor.start()

        settings.dragSnappingEnabled = false
        XCTAssertFalse(monitor.isMonitoring)
        XCTAssertEqual(monitors.uninstalls, 1)

        settings.dragSnappingEnabled = true
        XCTAssertTrue(monitor.isMonitoring)
        XCTAssertEqual(monitors.installs, 2)
    }

    func testStartingTwiceDoesNotInstallTwice() {
        let monitors = FakeMonitors()
        let monitor = EdgeDragMonitor(settings: makeSettings(dragSnapping: true), monitors: monitors)

        monitor.start()
        monitor.start()

        XCTAssertEqual(monitors.installs, 1, "a second start must not double-register the monitors")
    }

    func testStoppingUninstallsAndStopsFollowingTheSetting() {
        let monitors = FakeMonitors()
        let settings = makeSettings(dragSnapping: true)
        let monitor = EdgeDragMonitor(settings: settings, monitors: monitors)
        monitor.start()

        monitor.stop()
        XCTAssertFalse(monitor.isMonitoring)

        settings.dragSnappingEnabled = false
        settings.dragSnappingEnabled = true
        XCTAssertEqual(monitors.installs, 1, "a stopped monitor must not come back when the setting changes")
    }

    func testARefusedGlobalMonitorIsNotReportedAsMonitoring() {
        let monitors = FakeMonitors()
        monitors.succeeds = false
        let monitor = EdgeDragMonitor(settings: makeSettings(dragSnapping: true), monitors: monitors)

        monitor.start()

        XCTAssertFalse(monitor.isMonitoring, "without Accessibility trust there is no drag snapping")
    }
}

/// `AppSettings` reads its login-item state at init; this keeps these tests off the real one.
private struct NeverRegisteringLoginItems: LoginItemService {
    var status: SMAppService.Status { .notRegistered }
    func register() throws {}
    func unregister() throws {}
}
