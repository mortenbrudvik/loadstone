import XCTest
import ServiceManagement
@testable import Loadstone

@MainActor
final class AppSettingsTests: XCTestCase {
    private final class FakeLoginItems: LoginItemService {
        var status: SMAppService.Status = .notRegistered
        var statusAfterRegister: SMAppService.Status = .enabled
        var registerError: Error?
        var unregisterError: Error?
        var registerCalls = 0
        var unregisterCalls = 0

        func register() throws {
            registerCalls += 1
            if let registerError { throw registerError }
            status = statusAfterRegister
        }

        func unregister() throws {
            unregisterCalls += 1
            if let unregisterError { throw unregisterError }
            status = .notRegistered
        }
    }

    private struct Failure: Error {}

    private func scratchDefaults() -> UserDefaults {
        let name = "com.brudvik.loadstone.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
        return defaults
    }

    func testFailedRegistrationRollsTheToggleBackOnceWithoutRecursing() {
        let fake = FakeLoginItems()
        fake.registerError = Failure()
        fake.unregisterError = Failure()
        let settings = AppSettings(defaults: scratchDefaults(), loginItems: fake)

        settings.launchAtLogin = true

        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertEqual(fake.registerCalls, 1)
        XCTAssertEqual(fake.unregisterCalls, 0, "rollback must not fire the observer again")
        XCTAssertNotNil(settings.loginItemMessage)
    }

    func testRegistrationThatNeedsApprovalKeepsTheToggleOnAndExplains() {
        let fake = FakeLoginItems()
        fake.statusAfterRegister = .requiresApproval
        let settings = AppSettings(defaults: scratchDefaults(), loginItems: fake)

        settings.launchAtLogin = true

        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertEqual(settings.loginItemStatus, .requiresApproval)
        XCTAssertTrue(settings.loginItemMessage?.contains("Login Items") == true, "\(String(describing: settings.loginItemMessage))")
    }

    func testSuccessfulRegistrationClearsAnyMessage() {
        let fake = FakeLoginItems()
        let settings = AppSettings(defaults: scratchDefaults(), loginItems: fake)

        settings.launchAtLogin = true

        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertNil(settings.loginItemMessage)
        XCTAssertEqual(fake.registerCalls, 1)
    }

    func testTurningOffUnregisters() {
        let fake = FakeLoginItems()
        fake.status = .enabled
        let settings = AppSettings(defaults: scratchDefaults(), loginItems: fake)
        XCTAssertTrue(settings.launchAtLogin, "initial state mirrors the service")

        settings.launchAtLogin = false

        XCTAssertEqual(fake.unregisterCalls, 1)
        XCTAssertFalse(settings.launchAtLogin)
    }

    func testDragSnappingDefaultsToOnAndPersists() {
        let defaults = scratchDefaults()
        let first = AppSettings(defaults: defaults, loginItems: FakeLoginItems())
        XCTAssertTrue(first.dragSnappingEnabled)

        first.dragSnappingEnabled = false

        let second = AppSettings(defaults: defaults, loginItems: FakeLoginItems())
        XCTAssertFalse(second.dragSnappingEnabled)
    }
}
