import XCTest
import ApplicationServices
@testable import Loadstone

@MainActor
final class WindowDirectorTests: XCTestCase {
    private final class FakeWindow: MovableWindow {
        var identity: WindowIdentity?
        var cocoaFrame: CGRect?
        var writes: [CGRect] = []
        var rejectWith: AXError?

        init(frame: CGRect, identity: WindowIdentity? = .cgWindow(1, pid: 42)) {
            cocoaFrame = frame
            self.identity = identity
        }

        @discardableResult
        func setCocoaFrame(_ frame: CGRect) -> AXError {
            if let rejectWith { return rejectWith }
            writes.append(frame)
            cocoaFrame = frame
            return .success
        }
    }

    private let primary = Display(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 80, width: 1920, height: 975)
    )
    private let right = Display(
        frame: CGRect(x: 1920, y: -300, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1920, y: -300, width: 2560, height: 1415)
    )
    private let original = CGRect(x: 100, y: 100, width: 800, height: 600)

    private func makeDirector() -> WindowDirector {
        WindowDirector(displays: { [self.primary, self.right] })
    }

    func testTilePlacesTheWindowOnTheDisplayUnderItsCentre() {
        let window = FakeWindow(frame: original)
        let outcome = makeDirector().perform(.tile(.leftHalf), on: window)
        XCTAssertEqual(outcome, .moved)
        XCTAssertEqual(window.cocoaFrame, Tile.leftHalf.frame(in: primary.visibleFrame))
    }

    func testRestoreReturnsToTheFrameBeforeTheFirstCommand() {
        let window = FakeWindow(frame: original)
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)
        director.perform(.tile(.rightHalf), on: window)
        director.perform(.center, on: window)

        XCTAssertEqual(director.perform(.restore, on: window), .moved)
        XCTAssertEqual(window.cocoaFrame, original)
    }

    func testRestoreIsOneShot() {
        let window = FakeWindow(frame: original)
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)
        director.perform(.restore, on: window)
        let writesSoFar = window.writes.count

        XCTAssertEqual(director.perform(.restore, on: window), .nothingToRestore)
        XCTAssertEqual(window.writes.count, writesSoFar)
    }

    func testRestoreWithNothingRememberedWritesNothing() {
        let window = FakeWindow(frame: original)
        XCTAssertEqual(makeDirector().perform(.restore, on: window), .nothingToRestore)
        XCTAssertTrue(window.writes.isEmpty)
    }

    func testMovingToTheNextDisplayIsRememberedForRestore() {
        let window = FakeWindow(frame: original)
        let director = makeDirector()
        director.perform(.nextDisplay, on: window)
        XCTAssertNotEqual(window.cocoaFrame, original)

        director.perform(.restore, on: window)
        XCTAssertEqual(window.cocoaFrame, original)
    }

    func testNextDisplayMapsTheWindowProportionally() {
        let window = FakeWindow(frame: Tile.leftHalf.frame(in: primary.visibleFrame))
        makeDirector().perform(.nextDisplay, on: window)
        let expected = Tile.leftHalf.frame(in: right.visibleFrame)
        XCTAssertEqual(window.cocoaFrame!.minX, expected.minX, accuracy: 1e-6)
        XCTAssertEqual(window.cocoaFrame!.minY, expected.minY, accuracy: 1e-6)
        XCTAssertEqual(window.cocoaFrame!.width, expected.width, accuracy: 1e-6)
        XCTAssertEqual(window.cocoaFrame!.height, expected.height, accuracy: 1e-6)
    }

    func testPreviousDisplayWrapsAround() {
        let window = FakeWindow(frame: original)
        makeDirector().perform(.previousDisplay, on: window)
        XCTAssertTrue(right.visibleFrame.contains(window.cocoaFrame!), "\(window.cocoaFrame!)")
    }

    func testNextDisplayWithASingleDisplayReportsInsteadOfReapplying() {
        let window = FakeWindow(frame: original)
        let director = WindowDirector(displays: { [self.primary] })
        XCTAssertEqual(director.perform(.nextDisplay, on: window), .noOtherDisplay)
        XCTAssertTrue(window.writes.isEmpty)
    }

    func testSnapUsesTheGivenDisplayNotTheOneUnderTheWindow() {
        let window = FakeWindow(frame: original)
        let outcome = makeDirector().snap(.rightHalf, window: window, on: right)
        XCTAssertEqual(outcome, .moved)
        XCTAssertEqual(window.cocoaFrame, Tile.rightHalf.frame(in: right.visibleFrame))
    }

    func testCenterKeepsTheSize() {
        let window = FakeWindow(frame: original)
        makeDirector().perform(.center, on: window)
        XCTAssertEqual(window.cocoaFrame?.size, original.size)
        XCTAssertEqual(window.cocoaFrame?.midX, primary.visibleFrame.midX)
    }

    func testWindowOffEveryDisplayIsTiledOnThePrimary() {
        let window = FakeWindow(frame: CGRect(x: 9000, y: 9000, width: 300, height: 200))
        makeDirector().perform(.tile(.maximize), on: window)
        XCTAssertEqual(window.cocoaFrame, primary.visibleFrame)
    }

    func testRejectedFrameIsReportedNotSwallowed() {
        let window = FakeWindow(frame: original)
        window.rejectWith = .cannotComplete
        XCTAssertEqual(makeDirector().perform(.tile(.leftHalf), on: window), .rejected(.cannotComplete))
    }

    func testUnreadableFrameIsReported() {
        let window = FakeWindow(frame: original)
        window.cocoaFrame = nil
        XCTAssertEqual(makeDirector().perform(.tile(.leftHalf), on: window), .frameUnreadable)
    }

    func testForgettingAProcessDropsItsRestoreMemory() {
        let window = FakeWindow(frame: original)
        let director = makeDirector()
        director.perform(.tile(.leftHalf), on: window)

        director.forgetWindows(ofProcess: 42)

        XCTAssertEqual(director.perform(.restore, on: window), .nothingToRestore)
    }

    func testWindowsWithoutIdentityStillMoveButCannotRestore() {
        let window = FakeWindow(frame: original, identity: nil)
        let director = makeDirector()
        XCTAssertEqual(director.perform(.tile(.leftHalf), on: window), .moved)
        XCTAssertEqual(director.perform(.restore, on: window), .nothingToRestore)
    }
}
