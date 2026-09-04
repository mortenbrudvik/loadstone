import AppKit
import ApplicationServices
import XCTest
@testable import Loadstone

/// These need real Accessibility answers from the system, so like `AXWindowTests` they are
/// skipped in CI and run on a developer machine.
///
/// They rely on the test host being *untrusted*, which it is: the Debug build is ad-hoc signed
/// and gets a fresh identity on every rebuild, so TCC never has a grant for it. Each test says
/// so and skips rather than lying if that ever stops being true.
@MainActor
final class AccessibilityAuthTests: XCTestCase {
    private func requireUntrustedHost() throws {
        try XCTSkipIf(
            AccessibilityAuth.isTrusted,
            "this test host has been granted Accessibility, so it cannot show what an ungranted one reports"
        )
    }

    func testEffectiveTrustIsFalseWhileAccessibilityIsNotGranted() throws {
        try requireUntrustedHost()

        XCTAssertFalse(
            AccessibilityAuth.isEffectivelyTrusted,
            "the Settings pane would show a green \"Loadstone can move windows\" on a build that cannot move any"
        )
    }

    func testEveryCrossApplicationCallIsRefusedOnThisHost() throws {
        try requireUntrustedHost()
        let others = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != getpid() && !$0.isTerminated
        }
        try XCTSkipIf(others.isEmpty, "no other app to probe")

        // The ground truth the check above has to agree with: without a grant, reading another
        // app's focused window is answered with apiDisabled and nothing works.
        for app in others.prefix(3) {
            var value: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(
                AXUIElementCreateApplication(app.processIdentifier),
                kAXFocusedWindowAttribute as CFString,
                &value
            )
            XCTAssertEqual(error, .apiDisabled, "\(app.localizedName ?? "?") answered \(error.rawValue)")
        }
    }

    func testTheSystemWideElementCannotDetectAMissingGrant() throws {
        try requireUntrustedHost()

        // Why the check probes an application element rather than the system-wide one. This is
        // the bug that was: the system-wide element answers cannotComplete when untrusted and
        // never apiDisabled, so a probe keyed on apiDisabled reported an untrusted process as
        // working. If a future macOS starts answering apiDisabled here, this fails and the
        // simpler probe becomes available again.
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute as CFString, &value
        )

        XCTAssertNotEqual(error, .apiDisabled)
    }
}
